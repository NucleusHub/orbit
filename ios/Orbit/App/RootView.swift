import NucleusUI
import SwiftUI

struct RootView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(NucleusID.self) private var auth
    @Environment(Navigator.self) private var navigator
    @Environment(AppLock.self) private var lock
    @Environment(FilesStore.self) private var files
    @Environment(UploadQueue.self) private var uploads
    @Environment(\.scenePhase) private var scenePhase
    @State private var shielded = false
    @State private var launching = true

    private var connected: Bool { auth.isSignedIn || DebugLaunch.sampleData }

    var body: some View {
        @Bindable var navigator = navigator
        NavigationStack(path: $navigator.path) {
            Group {
                if connected { FolderPage(folderID: nil, name: nil) } else { SignedOutHome() }
            }
            .edgeSwipeBackOnly()
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .folder(let id, let name): FolderPage(folderID: id, name: name)
                case .search: SearchPage()
                case .settings: SettingsView()
                case .profile: ProfileView()
                }
            }
        }
        .sheet(item: $navigator.sheet, onDismiss: unlockDismissed) { sheet in
            sheetView(sheet)
                .modifier(ConfirmationDialog(inSheet: true))
        }
        .modifier(ConfirmationDialog(inSheet: false))
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                UploadPanel()
                ToastView()
            }
            .padding(.bottom, 24)
            .animation(NucleusMotion.quick, value: navigator.toast)
        }
        .onChange(of: lock.isLocked || shielded, initial: true) { _, covered in
            if covered { LockWindow.shared.show(lock: lock, colorScheme: preferences.appearance.colorScheme) } else { LockWindow.shared.hide() }
        }
        .overlay {
            if launching { LaunchHandover { launching = false } }
        }
        .task {
            lock.lockOnLaunch(enabled: preferences.appLock)
            auth.onSignedIn = { [files] in await files.syncNow() }
            auth.onSignedOut = { [files, navigator, uploads] _ in
                uploads.cancelAll()
                files.forget()
                navigator.path = []
                return true
            }
            auth.onExpired = { [files, uploads] in
                uploads.cancelAll()
                files.forget()
            }
            await DebugLaunch.presetFaceIDLock(files)
            DebugLaunch.route(navigator, files: files)
            if !preferences.hasSeenWelcome, !DebugLaunch.skipWelcome {
                try? await Task.sleep(for: .milliseconds(400))
                navigator.present(.welcome)
            }
            guard !DebugLaunch.fakeAccount else { return }
            await auth.validate()
            if connected { await files.loadSettings() }
        }
        .onOpenURL(perform: open)
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            guard preferences.shakeToReport, navigator.sheet == nil, !lock.isLocked else { return }
            Haptics.tap()
            navigator.present(.report)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                shielded = false
                lock.willEnterForeground(enabled: preferences.appLock)
                if !DebugLaunch.fakeAccount { Task { await auth.validate() } }
            case .inactive:
                // The app switcher's snapshot mustn't show what Face ID opened.
                if preferences.appLock || !files.faceIDPassed.isEmpty { shielded = true }
            case .background:
                if preferences.appLock || !files.faceIDPassed.isEmpty { shielded = true }
                lock.didEnterBackground()
                if !files.faceIDPassed.isEmpty, navigator.sheet != nil, navigator.sheet != .welcome { navigator.sheet = nil }
                files.relockFaceID()
            @unknown default: break
            }
        }
    }

    /// Cancelling the unlock prompt (swipe down or Cancel) runs its cancel action once.
    private func unlockDismissed() {
        // A sheet swapped for the unlock prompt finishes dismissing after the prompt is up; leave the prompt's actions alone.
        if case .unlock = navigator.sheet { return }
        navigator.afterUnlock = nil
        let cancel = navigator.onUnlockCancel
        navigator.onUnlockCancel = nil
        cancel?()
    }

    /// Setup files and links from a server's administrator, and `…://open?folder=<id>&highlight=<fileId>`.
    private func open(_ url: URL) {
        if url.isFileURL, url.pathExtension.lowercased() == "nucleusserver" {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            importServer { try NucleusServer.setup(fromFile: try Data(contentsOf: url)) }
            return
        }
        guard url.scheme == NucleusID.callbackScheme else { return }
        switch url.host() {
        case "server":
            importServer { try NucleusServer.setup(from: url) }
        case "open":
            guard connected else { return }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let folder = items.first { $0.name == "folder" }?.value
            navigator.sheet = nil
            navigator.highlight = items.first { $0.name == "highlight" }?.value
            navigator.path = folder.map { [.folder(id: $0, name: "")] } ?? []
        default: break
        }
    }

    /// A setup link or file from the server's administrator: confirm, then sign in with it filled in.
    private func importServer(_ read: () throws -> NucleusServer) {
        guard !auth.isSignedIn else {
            navigator.show(String(localized: "Sign out to switch servers."), icon: "exclamationmark.triangle.fill")
            return
        }
        let server: NucleusServer
        do {
            server = try read()
        } catch {
            let problem = error as? ServerProblem ?? .badSetup
            navigator.show(String(localized: problem.message), icon: "exclamationmark.triangle.fill")
            return
        }
        Task {
            let answer = await navigator.confirm(title: String(localized: "Use server \(server.host)?"), message: String(localized: "\(server.origin.absoluteString) will be used for signing in."),
                                                 actions: [String(localized: "Use server")])
            if answer == 0 { navigator.present(.signIn(server)) }
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: Sheet) -> some View {
        switch sheet {
        case .welcome: WelcomeView().interactiveDismissDisabled().presentationDragIndicator(.hidden)
        case .report: ReportSheet()
        case .signIn(let prefill): ServerSignInSheet(prefill: prefill)
        case .newFolder(let parent): NameSheet(mode: .newFolder(parentID: parent))
        case .rename(let item, let folder): NameSheet(mode: .rename(item, in: folder))
        case .password(let items, let folder): PasswordSheet(items: items, folderID: folder)
        case .unlock(let item): UnlockSheet(item: item).presentationDetents([.medium])
        case .move(let items, let folder): MoveSheet(items: items, from: folder)
        case .preview(let file, let folder): PreviewSheet(file: file, folderID: folder)
        }
    }
}

/// Questions asked through the navigator, shown over the sheet when one is open (a dialog can't show beneath it).
private struct ConfirmationDialog: ViewModifier {
    let inSheet: Bool
    @Environment(Navigator.self) private var navigator

    func body(content: Content) -> some View {
        let shown = navigator.confirmation.flatMap { (navigator.sheet != nil) == inSheet ? $0 : nil }
        content.confirmationDialog(shown?.title ?? "", isPresented: Binding(get: { shown != nil }, set: { if !$0, let shown { navigator.answer(shown.id, nil) } }),
                                   titleVisibility: .visible, presenting: shown) { c in
            ForEach(Array(c.actions.enumerated()), id: \.offset) { i, action in
                Button(action, role: c.destructive ? .destructive : nil) { navigator.answer(c.id, i) }
            }
        } message: { c in
            if let message = c.message { Text(message) }
        }
    }
}

/// Launch arguments for UI tests and screenshots. Debug builds only.
enum DebugLaunch {
    private static func has(_ flag: String) -> Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(flag)
        #else
        false
        #endif
    }

    /// Files from `SampleFiles` instead of a server.
    static var sampleData: Bool { has("-sampleData") }
    /// A made-up account for screenshots, never checked against the server.
    static var fakeAccount: Bool { has("-signedIn") }
    static var skipWelcome: Bool { has("-skipWelcome") }

    /// `-faceID pass|fail`: the simulator has no face to scan.
    static var authenticator: Authenticator? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-faceID"), i + 1 < args.count else { return nil }
        return ScriptedAuthenticator(passes: args[i + 1] == "pass")
        #else
        nil
        #endif
    }

    @MainActor
    static func prepare(preferences: Preferences) {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-resetAll") {
            preferences.hasSeenWelcome = false
            preferences.appLock = false
            preferences.viewMode = .grid
            NucleusSession.clear()
        }
        if args.contains("-appLock") { preferences.appLock = true }
        if args.contains("-signedIn") {
            NucleusSession(accessToken: "debug", refreshToken: "debug", expiresAt: .distantFuture,
                           user: .init(sub: "debug", handle: "honza", name: "Honza Kocanda", email: "honza@example.com")).save()
        }
        if let i = args.firstIndex(of: "-appearance"), i + 1 < args.count {
            preferences.appearance = AppearanceMode(rawValue: args[i + 1]) ?? .dark
        }
        if let i = args.firstIndex(of: "-view"), i + 1 < args.count {
            preferences.viewMode = ViewMode(rawValue: args[i + 1]) ?? .grid
        }
        #endif
    }

    /// `-faceIDLock <folder>[:strict]`: a sample root folder starts locked with Face ID.
    @MainActor
    static func presetFaceIDLock(_ files: FilesStore) async {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-faceIDLock"), i + 1 < args.count else { return }
        let parts = args[i + 1].split(separator: ":").map(String.init)
        try? await files.load(nil)
        guard let folder = files.listing(nil)?.folders.first(where: { $0.name == parts[0] }) else { return }
        try? await files.setFaceIDLock(.folder(folder), strict: parts.count > 1)
        #endif
    }

    @MainActor
    static func route(_ navigator: Navigator, files: FilesStore) {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-route"), i + 1 < args.count else { return }
        switch args[i + 1] {
        case "settings": navigator.path = [.settings]
        case "profile": navigator.path = [.settings, .profile]
        case "search": navigator.path = [.search]
        case "welcome": navigator.sheet = .welcome
        case "signin": navigator.sheet = .signIn(nil)
        case "report": navigator.sheet = .report
        case "newfolder": navigator.sheet = .newFolder(parentID: nil)
        default:
            // `-route folder:<name>` and `-route preview:<filename>`, looked up in the sample root.
            let parts = args[i + 1].split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            Task {
                try? await files.load(nil)
                guard let root = files.listing(nil) else { return }
                switch parts[0] {
                case "folder": if let f = root.folders.first(where: { $0.name == parts[1] }) { navigator.path = [.folder(id: f.id, name: f.name)] }
                case "preview": if let f = root.files.first(where: { $0.filename == parts[1] }) { navigator.sheet = .preview(f, in: nil) }
                case "move": if let f = root.files.first(where: { $0.filename == parts[1] }) { navigator.sheet = .move([.file(f)], from: nil) }
                case "unlock": if let f = root.folders.first(where: { $0.name == parts[1] }) { navigator.sheet = .unlock(.folder(f)) }
                default: break
                }
            }
        }
        #endif
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

// Shakes reach the key window only; SwiftUI has no hook for them.
extension UIWindow {
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .deviceDidShake, object: nil) }
        super.motionEnded(motion, with: event)
    }
}
