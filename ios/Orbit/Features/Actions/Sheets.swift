import NucleusUI
import SwiftUI

/// New folder and rename (the web's CreateFolderModal, reused for renames).
struct NameSheet: View {
    enum Mode {
        case newFolder(parentID: String?)
        case rename(ItemRef, in: String?)
    }

    let mode: Mode
    @Environment(FilesStore.self) private var files
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var saving = false
    @State private var problem: String?
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var title: LocalizedStringKey {
        if case .rename = mode { return "Rename" }
        return "New folder"
    }

    var body: some View {
        NucleusSheetPage(title, confirmTitle: { if case .rename = mode { "Save" } else { "Create" } }(),
                         canConfirm: !trimmed.isEmpty && !saving && trimmed != original,
                         onCancel: { dismiss() }, onConfirm: save) {
            NucleusSection(footer: problem.map { Text(verbatim: $0).foregroundStyle(Nucleus.danger) }) {
                TextField(String(localized: "Name"), text: $name)
                    .font(.system(size: 17))
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .onChange(of: name) { _, v in if v.count > 255 { name = String(v.prefix(255)) } }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .accessibilityLabel("Name")
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            name = original
            focused = true
        }
    }

    private var original: String {
        if case .rename(let item, _) = mode { return item.name }
        return ""
    }

    private func save() {
        guard !trimmed.isEmpty, !saving, trimmed != original else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                switch mode {
                case .newFolder(let parent):
                    _ = try await files.createFolder(name: trimmed, in: parent)
                case .rename(let item, let folder):
                    try await files.rename(item, to: trimmed, in: folder)
                }
                Haptics.success()
                dismiss()
            } catch {
                Haptics.error()
                problem = error.orbitMessage
            }
        }
    }
}

/// Set, change or remove a password on one or more items (the web's SetPasswordModal).
struct PasswordSheet: View {
    let items: [ItemRef]
    let folderID: String?
    @Environment(FilesStore.self) private var files
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""
    @State private var saving = false
    @State private var problem: String?

    private var alreadyProtected: Bool { items.count == 1 && items[0].isProtected }

    var body: some View {
        NucleusSheetPage(alreadyProtected ? "Change password" : "Set password", confirmTitle: "Save",
                         canConfirm: !password.isEmpty && !saving, onCancel: { dismiss() }, onConfirm: save) {
            VStack(spacing: 20) {
                (items.count == 1 ? Text(verbatim: items[0].name) : Text("\(items.count) items"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Nucleus.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                NucleusSection(footer: problem.map { Text(verbatim: $0).foregroundStyle(Nucleus.danger) }
                    ?? Text("Anyone opening it will need this password. Folders protect what's directly inside them.")) {
                    NucleusField("Password", text: $password, secure: true)
                    NucleusField("Confirm password", text: $confirm, secure: true)
                }
                if alreadyProtected {
                    Button(role: .destructive) { apply(nil) } label: {
                        Text("Remove password").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NucleusSecondaryButtonStyle())
                    .disabled(saving)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        guard password == confirm else {
            Haptics.error()
            problem = String(localized: "Passwords don't match")
            return
        }
        apply(password)
    }

    private func apply(_ value: String?) {
        saving = true
        Task {
            defer { saving = false }
            do {
                try await files.setPassword(items, value, in: folderID)
                Haptics.success()
                navigator.show(value == nil ? String(localized: "Password removed") : String(localized: "Password set"), icon: value == nil ? "lock.open.fill" : "lock.fill")
                dismiss()
            } catch {
                Haptics.error()
                problem = error.orbitMessage
            }
        }
    }
}

/// The password prompt for a protected folder or file (the web's PasswordPromptModal).
struct UnlockSheet: View {
    let item: ItemRef
    @Environment(FilesStore.self) private var files
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var checking = false
    @State private var problem: String?

    var body: some View {
        NucleusSheetPage(item.isFolder ? "Folder is protected" : "File is protected", confirmTitle: "Unlock",
                         canConfirm: !password.isEmpty && !checking, onCancel: { dismiss() }, onConfirm: unlock) {
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(NucleusTint.amber.gradient)
                    .padding(.top, 8)
                Text(verbatim: item.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Nucleus.secondaryText)
                NucleusSection(footer: problem.map { Text(verbatim: $0).foregroundStyle(Nucleus.danger) }) {
                    NucleusField("Password", text: $password, secure: true)
                        .onSubmit(unlock)
                }
            }
        }
    }

    private func unlock() {
        guard !password.isEmpty, !checking else { return }
        checking = true
        Task {
            defer { checking = false }
            do {
                switch item {
                case .folder(let f): try await files.open(folderID: f.id, password: password)
                case .file(let f): try await files.unlock(f, password: password)
                }
                Haptics.success()
                let then = navigator.afterUnlock
                navigator.afterUnlock = nil
                navigator.onUnlockCancel = nil
                navigator.sheet = nil
                // The next sheet (rename, preview…) replaces this one.
                then?()
            } catch {
                Haptics.error()
                problem = (error as? OrbitError) == .wrongPassword ? String(localized: "Wrong password") : String(localized: "Verification failed: \(error.orbitMessage)")
            }
        }
    }
}

/// Pick a destination folder (the web's MoveModal).
struct MoveSheet: View {
    let items: [ItemRef]
    let folderID: String?
    @Environment(FilesStore.self) private var files
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss
    @State private var tree: MoveTree?
    @State private var target: String??
    @State private var expanded: Set<String> = []
    @State private var moving = false
    @State private var problem: String?

    init(items: [ItemRef], from folderID: String?) {
        self.items = items
        self.folderID = folderID
    }

    private var canMove: Bool {
        guard let tree, case .some(let t) = target else { return false }
        return !tree.isDisabled(t) && !moving
    }

    var body: some View {
        NucleusSheetPage("Move", confirmTitle: "Move here", canConfirm: canMove, onCancel: { dismiss() }, onConfirm: move) {
            VStack(alignment: .leading, spacing: 16) {
                (items.count == 1 ? Text("Move “\(items[0].name)” to…") : Text("Move \(items.count) items to…"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Nucleus.secondaryText)
                    .padding(.horizontal, 4)
                if let tree {
                    NucleusSection(footer: problem.map { Text(verbatim: $0).foregroundStyle(Nucleus.danger) }) {
                        row(id: nil, name: String(localized: "Home"), icon: "house.fill", depth: 0, hasChildren: false, tree: tree)
                        ForEach(flatten(tree.roots, depth: 0), id: \.node.id) { entry in
                            row(id: entry.node.id, name: entry.node.name, icon: entry.node.folder.isGroupRoot ? "person.2.fill" : "folder.fill",
                                depth: entry.depth + 1, hasChildren: !entry.node.children.isEmpty, tree: tree)
                        }
                    }
                } else if let problem {
                    NucleusEmptyState("exclamationmark.triangle", title: "Couldn't load folders", message: LocalizedStringKey(problem))
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
        }
        .task {
            do {
                tree = MoveTree(folders: try await files.service.allFolders(), moving: items, sealed: files.sealedFolders)
            } catch {
                problem = error.orbitMessage
            }
        }
    }

    private func flatten(_ nodes: [MoveTree.Node], depth: Int) -> [(node: MoveTree.Node, depth: Int)] {
        nodes.flatMap { n in [(n, depth)] + (expanded.contains(n.id) ? flatten(n.children, depth: depth + 1) : []) }
    }

    private func row(id: String?, name: String, icon: String, depth: Int, hasChildren: Bool, tree: MoveTree) -> some View {
        let disabled = tree.isDisabled(id)
        let chosen = target == .some(id)
        return Button {
            guard !disabled else { return }
            Haptics.selection()
            target = .some(id)
        } label: {
            HStack(spacing: 10) {
                if hasChildren, let id {
                    Button {
                        withAnimation(NucleusMotion.quick) { if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) } }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .rotationEffect(.degrees(expanded.contains(id) ? 90 : 0))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Nucleus.secondaryText)
                    .accessibilityLabel(expanded.contains(id) ? "Collapse" : "Expand")
                } else {
                    Color.clear.frame(width: 24, height: 24)
                }
                Image(systemName: id.map { files.sealedFolders.contains($0) } == true ? "faceid" : icon).foregroundStyle(Nucleus.accent)
                Text(verbatim: name).foregroundStyle(disabled ? Nucleus.secondaryText : Nucleus.primaryText).lineLimit(1)
                if disabled { Text("Current").font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText) }
                Spacer()
                if chosen { Image(systemName: "checkmark").foregroundStyle(Nucleus.accent).fontWeight(.semibold) }
            }
            .font(.system(size: 16))
            .padding(.leading, 8 + CGFloat(depth) * 18)
            .padding(.trailing, 16)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(NucleusRowButtonStyle())
    }

    private func move() {
        guard case .some(let destination) = target else { return }
        moving = true
        Task {
            defer { moving = false }
            do {
                try await files.move(items, to: destination, from: folderID)
                Haptics.success()
                navigator.show(items.count == 1 ? String(localized: "Moved") : String(localized: "Moved \(items.count) items"), icon: "folder.fill")
                dismiss()
            } catch {
                Haptics.error()
                problem = error.orbitMessage
            }
        }
    }
}
