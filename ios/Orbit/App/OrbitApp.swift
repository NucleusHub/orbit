import NucleusUI
import SwiftUI

@main
struct OrbitApp: App {
    @State private var preferences: Preferences
    @State private var auth: NucleusID
    @State private var navigator = Navigator()
    @State private var lock = AppLock()
    @State private var files: FilesStore
    @State private var uploads: UploadQueue

    init() {
        let preferences = Preferences()
        DebugLaunch.prepare(preferences: preferences)
        let auth = NucleusID()
        let files = FilesStore(service: DebugLaunch.sampleData ? SampleFiles() : OrbitClient(auth: auth),
                               authenticator: DebugLaunch.authenticator ?? LocalAuthenticator())
        _preferences = State(initialValue: preferences)
        _auth = State(initialValue: auth)
        _files = State(initialValue: files)
        _uploads = State(initialValue: UploadQueue(store: files))
        Haptics.warmUp()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(preferences)
                .environment(auth)
                .environment(navigator)
                .environment(lock)
                .environment(files)
                .environment(uploads)
                .preferredColorScheme(preferences.appearance.colorScheme)
                .nucleusAccentTint()
        }
    }
}
