import NucleusUI
import SwiftUI

/// What tapping or long-pressing a file or folder does, shared by folder pages and search (the web's card menus).
@MainActor
struct ItemActions {
    let files: FilesStore
    let navigator: Navigator
    /// The folder the items are listed in; nil at the root and in search results.
    let folderID: String?

    func open(_ item: ItemRef) {
        faceID(item) { reallyOpen(item) }
    }

    /// Face ID first for a locked item; its fallback may be the Orbit password prompt.
    func faceID(_ item: ItemRef, then action: @escaping () -> Void) {
        guard files.isFaceIDLocked(item) else { return action() }
        Task {
            switch await files.passFaceID(for: item) {
            case .success: action()
            case .usePassword: navigator.unlock(item, then: action)
            case .cancelled: break
            case .failed(let message):
                Haptics.error()
                navigator.show(message, icon: "faceid")
            }
        }
    }

    private func reallyOpen(_ item: ItemRef) {
        switch item {
        case .folder(let folder):
            navigator.open(.folder(id: folder.id, name: folder.name))
        case .file(let file):
            if files.resolvedURL(for: file) == nil {
                verified(item) { navigator.present(.preview(file, in: folderID)) }
            } else {
                navigator.present(.preview(file, in: folderID))
            }
        }
    }

    /// The Orbit password, unless Face ID already stands in for it (saved on this device after the first time).
    private func verified(_ item: ItemRef, _ action: @escaping () -> Void) {
        Task {
            if await files.autoUnlock(item) { return action() }
            if case .file(let f) = item, files.resolvedURL(for: f) != nil { return action() }
            if case .folder = item, !files.needsVerification(item) { return action() }
            navigator.unlock(item, then: action)
        }
    }

    /// Dropping a dragged file or folder onto a folder (or Home) moves it there, as on the web.
    func drop(_ payload: DragPayload, into target: OrbitFolder?) {
        guard payload.canDrop(into: target?.id) else { return }
        let item: ItemRef? = switch payload.kind {
        case .file: files.file(payload.id).map(ItemRef.file)
        case .folder: files.folder(payload.id).map(ItemRef.folder)
        }
        guard let item, item.canEdit else { return }
        let current: String? = switch item {
        case .file(let f): f.folderId
        case .folder(let f): f.parentId
        }
        guard current != target?.id else { return }
        gated(item) {
            let move = {
                Task {
                    do {
                        try await files.move([item], to: target?.id, from: folderID)
                        Haptics.success()
                        navigator.show(String(localized: "Moved “\(item.name)” to \(target?.name ?? String(localized: "Home"))"), icon: "folder.fill")
                    } catch { navigator.fail(error) }
                }
            }
            // Into a Face ID folder only with Face ID, like opening it.
            if let target { faceID(.folder(target)) { _ = move() } } else { _ = move() }
        }
    }

    /// Edits on a protected item ask for its password first (`withAuth` on the web).
    func gated(_ item: ItemRef, _ action: @escaping () -> Void) {
        faceID(item) {
            if files.needsVerification(item) { verified(item, action) } else { action() }
        }
    }

    /// Setting, changing or removing a Face ID lock proves Face ID works first, at the stricter of old and new.
    func setFaceIDLock(_ item: ItemRef, strict: Bool?) {
        let current = files.ownFaceIDLock(item)
        let mustBeStrict = (current?.strict ?? false) || (strict ?? false)
        Task {
            let reason = strict == nil ? String(localized: "Remove the Face ID lock") : String(localized: "Lock “\(item.name)” with Face ID")
            switch await files.authenticator.authenticate(reason: reason, strict: mustBeStrict, passwordFallback: false) {
            case .success:
                do {
                    try await files.setFaceIDLock(item, strict: strict)
                    Haptics.success()
                    navigator.show(strict == nil ? String(localized: "Face ID lock removed") : String(localized: "Locked with Face ID"), icon: "faceid")
                } catch { navigator.fail(error) }
            case .cancelled, .usePassword: break
            case .failed(let message):
                Haptics.error()
                navigator.show(message, icon: "faceid")
            }
        }
    }

    func rename(_ item: ItemRef) { gated(item) { navigator.present(.rename(item, in: folderID)) } }
    func move(_ items: [ItemRef]) { gatedAll(items) { navigator.present(.move(items, from: folderID)) } }
    func password(_ items: [ItemRef]) { gatedAll(items) { navigator.present(.password(items, in: folderID)) } }

    func convert(_ file: OrbitFile) {
        gated(.file(file)) {
            Task {
                do {
                    try await files.transcode(file, in: folderID)
                    navigator.show(String(localized: "Conversion queued"), icon: "arrow.triangle.2.circlepath")
                } catch { navigator.fail(error) }
            }
        }
    }

    func share(_ file: OrbitFile) {
        faceID(.file(file)) {
            Task {
                do { try await ShareExport.share(file, files: files) } catch { navigator.fail(error) }
            }
        }
    }

    @ViewBuilder
    private func faceIDMenu(for item: ItemRef) -> some View {
        let lock = files.ownFaceIDLock(item)
        Menu {
            Button { setFaceIDLock(item, strict: false) } label: {
                Label("Face ID or passcode", systemImage: lock?.strict == false ? "checkmark" : "faceid")
            }
            Button { setFaceIDLock(item, strict: true) } label: {
                Label("Face ID only", systemImage: lock?.strict == true ? "checkmark" : "lock.shield")
            }
            if lock != nil {
                Divider()
                Button(role: .destructive) { setFaceIDLock(item, strict: nil) } label: { DestructiveLabel("Remove Face ID lock", systemImage: "lock.open") }
            }
        } label: {
            Label(lock == nil ? "Lock with Face ID" : "Face ID lock", systemImage: "faceid")
        }
    }

    func delete(_ items: [ItemRef], then done: @escaping () -> Void = {}) {
        gatedAll(items) {
            Task {
                let title = items.count == 1 ? String(localized: "Delete “\(items[0].name)”?") : String(localized: "Delete \(items.count) items?")
                var message = String(localized: "This can't be undone.")
                if items.contains(where: \.isFolder) { message += " " + String(localized: "Everything inside goes too.") }
                guard await navigator.confirm(title: title, message: message, actions: [String(localized: "Delete")], destructive: true) == 0 else { return }
                do {
                    try await files.delete(items, from: folderID)
                    Haptics.success()
                    done()
                } catch { navigator.fail(error) }
            }
        }
    }

    /// Bulk actions ask for each protected item's password in turn.
    private func gatedAll(_ items: [ItemRef], _ action: @escaping () -> Void) {
        if let next = items.first(where: files.isFaceIDLocked) { return faceID(next) { gatedAll(items, action) } }
        guard let next = items.first(where: files.needsVerification) else { return action() }
        navigator.unlock(next) { gatedAll(items, action) }
    }

    @ViewBuilder
    func menu(for item: ItemRef) -> some View {
        if files.isFaceIDLocked(item) {
            // Nothing else until Face ID passes.
            Button { open(item) } label: { Label("Unlock with Face ID", systemImage: "faceid") }
        } else {
            unlockedMenu(for: item)
        }
    }

    @ViewBuilder
    private func unlockedMenu(for item: ItemRef) -> some View {
        switch item {
        case .folder:
            Button { open(item) } label: { Label("Open", systemImage: "folder") }
        case .file(let file):
            if files.resolvedURL(for: file) == nil {
                Button { open(item) } label: { Label("Unlock", systemImage: "lock.open") }
            } else {
                Button { open(item) } label: { Label("Preview", systemImage: "eye") }
                Button { share(file) } label: { Label("Share or save", systemImage: "square.and.arrow.up") }
            }
        }
        faceIDMenu(for: item)
        if item.canEdit {
            Divider()
            Button { move([item]) } label: { Label("Move", systemImage: "folder.badge.gearshape") }
            Button { rename(item) } label: { Label("Rename", systemImage: "pencil") }
            Button { password([item]) } label: {
                Label(item.isProtected ? "Change password" : "Set password", systemImage: item.isProtected ? "lock.rotation" : "lock")
            }
            if case .file(let file) = item, file.canConvert {
                Button { convert(file) } label: { Label("Convert", systemImage: "arrow.triangle.2.circlepath") }
            }
            Divider()
            Button(role: .destructive) { delete([item]) } label: { DestructiveLabel("Delete", systemImage: "trash") }
        }
    }
}
