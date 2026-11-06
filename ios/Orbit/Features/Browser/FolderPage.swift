import NucleusUI
import PhotosUI
import SwiftUI

/// One folder (or the root): header, breadcrumbs, then its folders and files (the web's FilesView).
struct FolderPage: View {
    let folderID: String?
    let name: String?

    @Environment(FilesStore.self) private var files
    @Environment(Navigator.self) private var navigator
    @Environment(Preferences.self) private var preferences
    @Environment(UploadQueue.self) private var uploads
    @Environment(\.dismiss) private var dismiss

    @State private var problem: String?
    @State private var locked = false
    @State private var selection: Set<String>?
    @State private var pickingPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importingFiles = false
    @State private var importingFolder = false
    @State private var highlight: String?
    @State private var faceIDProblem: String?

    private var listing: Listing? { faceLocked ? nil : files.listing(folderID) }
    private var faceLocked: Bool { folderID.map { files.isFaceIDLocked(folderID: $0) } ?? false }
    private var actions: ItemActions { ItemActions(files: files, navigator: navigator, folderID: folderID) }
    private var title: String {
        guard let folderID else { return "Orbit" }
        return listing?.breadcrumbs.last?.name ?? (name?.isEmpty == false ? name : nil) ?? files.folderName(folderID) ?? ""
    }

    var body: some View {
        ZStack {
            NucleusBackground()
            VStack(spacing: 0) {
                header
                content
            }
        }
        .overlay(alignment: .bottom) {
            if let selection {
                SelectionBar(count: selection.count, actions: selectionActions(selection)) { self.selection = nil }
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(NucleusMotion.quick, value: selection != nil)
        .onChange(of: listing) { _, now in
            // Moved or deleted items leave the selection with them.
            guard let now, let current = selection else { return }
            selection = current.intersection(now.folders.map { ItemRef.folder($0).id } + now.files.map { ItemRef.file($0).id })
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            do {
                try await files.ensureKnown(folderID)
            } catch {
                problem = String(localized: "Couldn't check this folder's Face ID lock. \(error.orbitMessage)")
                return
            }
            if faceLocked { await unlockFaceID() } else { await load() }
        }
        .onAppear { if listing != nil { Task { await files.refresh(folderID) } } }
        .onChange(of: faceLocked) { _, locked in if locked { selection = nil } }
        .task(id: files.needsPolling(folderID) && !faceLocked) {
            // Conversions only report progress through listings, so the web polls every 3 s too.
            while files.needsPolling(folderID), !faceLocked, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await files.refresh(folderID)
            }
        }
        .photosPicker(isPresented: $pickingPhotos, selection: $photoItems, matching: .any(of: [.images, .videos]), photoLibrary: .shared())
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            uploads.enqueuePhotos(items, into: folderID)
        }
        .fileImporter(isPresented: $importingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { uploads.enqueue(urls, into: folderID) }
        }
        .fileImporter(isPresented: $importingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { uploads.enqueueFolder(url, into: folderID) }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if folderID != nil {
                    GlassCircleButton("chevron.left") { dismiss() }
                        .accessibilityLabel("Back")
                }
                GlassCircleButton("magnifyingglass") { navigator.open(.search) }
                    .accessibilityLabel("Search")
                Spacer()
                if selection == nil {
                    addMenu
                    moreMenu
                    if folderID == nil {
                        GlassCircleButton("gearshape") { navigator.open(.settings) }
                            .accessibilityLabel("Settings")
                    }
                } else {
                    Button("Done") { selection = nil }
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .nucleusGlass(in: Capsule(), interactive: true)
                }
            }
            Text(verbatim: title)
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Nucleus.primaryText)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.top, 6)
            if let crumbs = listing?.breadcrumbs, folderID != nil {
                BreadcrumbBar(crumbs: crumbs) { payload, target in actions.drop(payload, into: target) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var addMenu: some View {
        Menu {
            Button { pickingPhotos = true } label: { Label("Upload photos and videos", systemImage: "photo.on.rectangle") }
            Button { importingFiles = true } label: { Label("Upload files", systemImage: "doc.badge.plus") }
            Button { importingFolder = true } label: { Label("Upload a folder", systemImage: "folder.badge.plus") }
            Divider()
            Button { navigator.present(.newFolder(parentID: folderID)) } label: { Label("New folder", systemImage: "folder.badge.plus") }
        } label: {
            GlassCircleLabel("plus", tint: Nucleus.accent)
        }
        .accessibilityLabel("Add")
        .disabled(locked || faceLocked)
    }

    private var moreMenu: some View {
        Menu {
            Picker(selection: Binding(get: { preferences.viewMode }, set: { preferences.viewMode = $0 })) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode == .grid ? "square.grid.2x2" : "list.bullet").tag(mode)
                }
            } label: { Text("View") }
            Button { selection = [] } label: { Label("Select", systemImage: "checkmark.circle") }
                .disabled(listing?.isEmpty ?? true)
            Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(faceLocked)
        } label: {
            GlassCircleLabel("ellipsis")
        }
        .accessibilityLabel("More")
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if faceLocked {
            Spacer()
            VStack(spacing: 16) {
                NucleusEmptyState("faceid", title: "Locked with Face ID", message: faceIDProblem.map { LocalizedStringKey($0) } ?? "Unlock to see what's inside.")
                Button { Task { await unlockFaceID() } } label: { Label("Unlock with Face ID", systemImage: "faceid") }
                    .buttonStyle(NucleusPrimaryButtonStyle())
                    .fixedSize()
            }
            Spacer()
            Spacer()
        } else if let listing {
            ScrollViewReader { proxy in
                ScrollView {
                    if listing.isEmpty {
                        emptyFolder.padding(.top, 40)
                    } else {
                        ItemsView(listing: listing, actions: actions, mode: preferences.viewMode, selection: $selection, highlight: highlight)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, selection == nil ? 120 : 160)
                    }
                }
                .refreshable { await load() }
                .onChange(of: listing.files.map(\.id), initial: true) { _, ids in pointOut(in: ids, proxy: proxy) }
            }
        } else if let problem {
            Spacer()
            VStack(spacing: 16) {
                NucleusEmptyState(locked ? "lock.fill" : "exclamationmark.triangle", title: locked ? "Folder is protected" : "Couldn't load this folder",
                                  message: LocalizedStringKey(problem))
                Button(locked ? "Unlock" : "Try again") {
                    if locked { askPassword() } else { Task { await load() } }
                }
                    .buttonStyle(NucleusSecondaryButtonStyle())
                    .fixedSize()
            }
            Spacer()
            Spacer()
        } else {
            Spacer()
            ProgressView().controlSize(.large)
            Spacer()
        }
    }

    private var emptyFolder: some View {
        VStack(spacing: 18) {
            NucleusEmptyState("tray", title: "This folder is empty", message: "Upload photos or files, or create a folder.")
            HStack(spacing: 10) {
                Button { pickingPhotos = true } label: { Label("Upload", systemImage: "arrow.up") }
                    .buttonStyle(NucleusPrimaryButtonStyle())
                Button { navigator.present(.newFolder(parentID: folderID)) } label: { Label("New folder", systemImage: "folder.badge.plus") }
                    .buttonStyle(NucleusSecondaryButtonStyle())
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Loading

    private func load() async {
        guard !faceLocked else { return }
        do {
            try await files.load(folderID)
            problem = nil
            locked = false
        } catch OrbitError.folderLocked {
            locked = true
            problem = String(localized: "Enter the password to see what's inside.")
            askPassword()
        } catch {
            if listing == nil { problem = error.orbitMessage } else { navigator.fail(error) }
        }
    }

    private func unlockFaceID() async {
        guard let folderID else { return }
        let folder = files.folder(folderID) ?? OrbitFolder(id: folderID, name: title)
        switch await files.passFaceID(for: .folder(folder)) {
        case .success:
            faceIDProblem = nil
            await load()
        case .usePassword:
            askPassword()
        case .cancelled:
            break
        case .failed(let message):
            Haptics.error()
            faceIDProblem = message
        }
    }

    private func askPassword() {
        guard let folderID else { return }
        let folder = OrbitFolder(id: folderID, name: title, protected: true)
        navigator.unlock(.folder(folder)) {
            locked = false
            problem = nil
        } onCancel: {
            // The web goes back to the parent when the prompt is cancelled.
            dismiss()
        }
    }

    /// A deep link's file: scroll to it and outline it for a moment.
    private func pointOut(in ids: [String], proxy: ScrollViewProxy) {
        guard let target = navigator.highlight, ids.contains(target) else { return }
        navigator.highlight = nil
        withAnimation(NucleusMotion.ease) { proxy.scrollTo(target, anchor: .center) }
        highlight = target
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(NucleusMotion.quick) { highlight = nil }
        }
    }

    private func selectionActions(_ ids: Set<String>) -> SelectionBar.Actions {
        let items = ((listing?.folders.map(ItemRef.folder) ?? []) + (listing?.files.map(ItemRef.file) ?? [])).filter { ids.contains($0.id) }
        return SelectionBar.Actions(
            move: { actions.move(items) },
            password: { actions.password(items) },
            delete: { actions.delete(items) { selection = nil } }
        )
    }
}

/// `GlassCircleButton`'s look, for menus.
struct GlassCircleLabel: View {
    let systemImage: String
    var tint: Color?

    init(_ systemImage: String, tint: Color? = nil) {
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint ?? Nucleus.glyph)
            .frame(width: 40, height: 40)
            .contentShape(Circle())
            .nucleusGlass(in: Circle(), interactive: true)
    }
}

/// Home › … › here; tapping a crumb goes back to it.
struct BreadcrumbBar: View {
    let crumbs: [Breadcrumb]
    /// Dropping onto Home or a parent moves the item up there (the web's ".." tile).
    var onDrop: ((DragPayload, OrbitFolder?) -> Void)?
    @Environment(Navigator.self) private var navigator
    @State private var targeted: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                crumb(Text("Home"), last: false) { navigator.path.removeAll { if case .folder = $0 { true } else { false } } }
                    .modifier(CrumbDrop(id: "home", target: nil, targeted: $targeted, onDrop: onDrop))
                ForEach(Array(crumbs.enumerated()), id: \.element.id) { i, c in
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Nucleus.secondaryText)
                    crumb(Text(verbatim: c.name), last: i == crumbs.count - 1) { go(to: c, depth: i + 1) }
                        .modifier(CrumbDrop(id: c.id, target: i == crumbs.count - 1 ? nil : OrbitFolder(id: c.id, name: c.name),
                                            targeted: $targeted, onDrop: i == crumbs.count - 1 ? nil : onDrop))
                }
            }
            .padding(.horizontal, 4)
        }
        .font(.system(size: 13, weight: .medium))
    }

    private func crumb(_ label: Text, last: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            label.foregroundStyle(last ? Nucleus.primaryText : Nucleus.secondaryText)
        }
        .disabled(last)
    }

    /// Pops to the crumb when it's on the stack, else rebuilds the stack (a deep link opened mid-tree).
    private func go(to crumb: Breadcrumb, depth: Int) {
        if let i = navigator.path.lastIndex(of: .folder(id: crumb.id, name: crumb.name)) ?? navigator.path.lastIndex(where: {
            if case .folder(let id, _) = $0 { id == crumb.id } else { false }
        }) {
            navigator.path = Array(navigator.path.prefix(i + 1))
        } else {
            navigator.path = crumbs.prefix(depth).map { .folder(id: $0.id, name: $0.name) }
        }
    }
}

/// A breadcrumb that takes drops, highlighted while something hovers over it.
private struct CrumbDrop: ViewModifier {
    let id: String
    let target: OrbitFolder?
    @Binding var targeted: String?
    let onDrop: ((DragPayload, OrbitFolder?) -> Void)?

    func body(content: Content) -> some View {
        if let onDrop {
            content
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Capsule().fill(Nucleus.accent.opacity(targeted == id ? 0.25 : 0)))
                .dropDestination(for: String.self) { texts, _ in
                    guard let payload = texts.first.flatMap(DragPayload.init(text:)), payload.canDrop(into: target?.id) else { return false }
                    onDrop(payload, target)
                    return true
                } isTargeted: { targeted = $0 ? id : (targeted == id ? nil : targeted) }
        } else {
            content
        }
    }
}

/// "N selected" with the bulk actions (the web's SelectionToolbar).
struct SelectionBar: View {
    struct Actions {
        let move: () -> Void
        let password: () -> Void
        let delete: () -> Void
    }

    let count: Int
    let actions: Actions
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count) selected")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Nucleus.primaryText)
                .contentTransition(.numericText())
                .padding(.leading, 14)
            Spacer()
            barButton("folder", "Move", action: actions.move)
            barButton("lock", "Password", action: actions.password)
            barButton("trash", "Delete", tint: Nucleus.danger, action: actions.delete)
        }
        .padding(6)
        .frame(height: 60)
        .nucleusGlass(in: Capsule(), interactive: true)
        .padding(.horizontal, 16)
        .disabled(count == 0)
    }

    private func barButton(_ icon: String, _ title: LocalizedStringKey, tint: Color = Nucleus.glyph, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(count == 0 ? Nucleus.secondaryText : tint)
            .frame(width: 64, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(NucleusPressStyle())
        .accessibilityLabel(Text(title))
    }
}
