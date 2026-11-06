import NucleusUI
import SwiftUI

struct SettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(NucleusID.self) private var auth
    @Environment(FilesStore.self) private var files
    @Environment(AppLock.self) private var lock
    @Environment(Navigator.self) private var navigator
    @Environment(\.openURL) private var openURL

    @State private var askingSignOut = false
    @State private var converting = false

    private var connected: Bool { auth.isSignedIn || DebugLaunch.sampleData }

    var body: some View {
        NucleusPage("Settings") {
            accountSection
            NucleusSection("Appearance") {
                NucleusSegmented(selection: Binding(get: { preferences.appearance }, set: { preferences.appearance = $0 }),
                                 items: AppearanceMode.allCases.map { ($0, $0.title) }, fill: true)
                    .padding(12)
                NucleusAccentPicker(selection: Binding(get: { NucleusTheme.shared.app }, set: { accent in
                    guard let accent else { return }
                    NucleusTheme.shared.app = accent
                    // Picked here, so the account's theme no longer replaces it until pushed to every app again.
                    UserDefaults.standard.set(Date(), forKey: "accentPickedAt")
                }))
            }
            NucleusSection("Browsing") {
                MenuRow(title: "Show files as", icon: IconTile("square.grid.2x2", tint: .indigo),
                        selection: Binding(get: { preferences.viewMode }, set: { preferences.viewMode = $0 }),
                        options: ViewMode.allCases.map { ($0, $0.title, $0 == .grid ? "square.grid.2x2" : "list.bullet") })
            }
            if connected { conversionSection }
            NucleusSection("Privacy", footer: Text("Locks Orbit after 30 seconds away and hides it in the app switcher.")) {
                toggle("Lock with \(lock.biometryName)", icon: lock.biometryIcon, tint: .indigo, isOn: Binding(get: { preferences.appLock }, set: { on in
                    Task {
                        if await lock.confirmOwner(reason: String(localized: "Confirm it's you")) { preferences.appLock = on }
                    }
                }))
            }
            helpSection
            aboutSection
        }
        .task { if connected, files.settings == nil { await files.loadSettings() } }
    }

    // MARK: Account

    private var accountSection: some View {
        NucleusSection("Account", footer: auth.error.map { Text(Self.message($0)) }) {
            if let user = auth.user {
                Button { navigator.open(.profile) } label: {
                    HStack(spacing: 12) {
                        Avatar(user: user)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: user.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Nucleus.primaryText)
                            Text(verbatim: "@\(user.handle) · \(NucleusID.origin.host() ?? "Nucleus ID")").font(.system(size: 13)).foregroundStyle(Nucleus.secondaryText)
                        }
                        Spacer()
                        Chevron()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NucleusRowButtonStyle())
                .accessibilityLabel(Text("Profile, \(user.name)"))
                Button {
                    Task {
                        if !DebugLaunch.fakeAccount { await auth.validate() }
                        await files.syncNow()
                    }
                } label: {
                    NucleusRow("Sync now", subtitle: syncStatusText, icon: IconTile("arrow.triangle.2.circlepath", tint: .emerald)) {
                        if files.syncing { ProgressView().controlSize(.small) }
                    }
                }
                .buttonStyle(NucleusRowButtonStyle())
                .disabled(files.syncing)
                Button { askingSignOut = true } label: { NucleusRow("Sign out", titleColor: Nucleus.danger) }
                    .buttonStyle(NucleusRowButtonStyle())
                    .confirmationDialog("Sign out?", isPresented: $askingSignOut, titleVisibility: .visible) {
                        Button("Sign out", role: .destructive) { Task { await auth.signOut(clean: true) } }
                    } message: {
                        Text("Your files stay on your Nucleus server.")
                    }
            } else {
                HStack(spacing: 12) {
                    Image("NucleusMark").resizable().scaledToFit().frame(width: 40, height: 40)
                    Text("Sign in with your Nucleus ID to reach the files on your server.")
                        .font(.system(size: 14)).foregroundStyle(Nucleus.glyph)
                }
                .padding(16)
                Button { navigator.present(.signIn(nil)) } label: {
                    NucleusRow("Sign in with Nucleus ID", icon: IconTile("person.crop.circle", tint: .indigo)) {
                        if auth.signingIn { ProgressView().controlSize(.small) } else { Chevron() }
                    }
                }
                .buttonStyle(NucleusRowButtonStyle())
                .disabled(auth.signingIn)
            }
        }
    }

    private var syncStatusText: Text {
        if files.syncing { return Text("Syncing…") }
        if let error = files.syncError { return Text(verbatim: error) }
        if let at = files.lastSynced { return Text("Synced \(at, format: .relative(presentation: .named))") }
        return Text("Reload everything from your server")
    }

    static func message(_ error: NucleusID.AuthError) -> String {
        switch error {
        case .expired: String(localized: "You were signed out. Sign in again to reach your files.")
        case .offline: String(localized: "Couldn't reach Nucleus ID. Check your connection.")
        case .keptUnsynced: String(localized: "Signed out.")
        case .failed(let reason): String(localized: "Sign-in failed: \(reason)")
        }
    }

    // MARK: Conversion (Orbit's own settings, stored on the server)

    private var conversionSection: some View {
        NucleusSection("Conversion", footer: Text("Applies to new uploads, so they play on every device.")) {
            if let settings = files.settings {
                toggle("Convert videos to MP4", icon: "film", tint: .violet, isOn: Binding(get: { settings.transcodeVideos }, set: { on in
                    var next = settings
                    next.transcodeVideos = on
                    save(next)
                }))
                toggle("Convert HEIC photos to JPEG", icon: "photo", tint: .emerald, isOn: Binding(get: { settings.convertImages }, set: { on in
                    var next = settings
                    next.convertImages = on
                    save(next)
                }))
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }.frame(minHeight: 52)
            }
            Button {
                Task {
                    converting = true
                    defer { converting = false }
                    do {
                        let n = try await files.convertAll()
                        navigator.show(n == 0 ? String(localized: "Nothing to convert") : String(localized: "Queued \(n) files"), icon: "arrow.triangle.2.circlepath")
                    } catch {
                        navigator.fail(error)
                    }
                }
            } label: {
                NucleusRow("Convert existing files", icon: IconTile("wand.and.stars", tint: .sky)) {
                    if converting { ProgressView().controlSize(.small) }
                }
            }
            .buttonStyle(NucleusRowButtonStyle())
            .disabled(converting)
        }
    }

    private func save(_ next: OrbitSettings) {
        Haptics.selection()
        Task {
            do { try await files.saveSettings(next) } catch { navigator.fail(error) }
        }
    }

    private func toggle(_ title: LocalizedStringKey, icon: String, tint: NucleusTint, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label { Text(title) } icon: { IconTile(icon, tint: tint) }.font(.system(size: 16))
        }
        .tint(Color(hex: 0x34C759))
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    // MARK: Help and About

    private var helpSection: some View {
        NucleusSection("Help") {
            Button { navigator.present(.welcome) } label: {
                NucleusRow("Show the welcome again", icon: IconTile("hand.wave.fill", tint: .orange)) { Chevron() }
            }
            .buttonStyle(NucleusRowButtonStyle())
            Button { navigator.present(.report) } label: {
                NucleusRow("Report a problem", icon: IconTile("ladybug.fill", tint: .rose)) { Chevron() }
            }
            .buttonStyle(NucleusRowButtonStyle())
            toggle("Shake to report", icon: "iphone.radiowaves.left.and.right", tint: .orange,
                   isOn: Binding(get: { preferences.shakeToReport }, set: { preferences.shakeToReport = $0 }))
        }
    }

    private var aboutSection: some View {
        NucleusSection("About") {
            NucleusRow("Version") {
                Text(verbatim: Bundle.main.versionString).foregroundStyle(Nucleus.secondaryText)
            }
            Button { openURL(NucleusID.privacyURL) } label: {
                NucleusRow("Privacy policy") { Image(systemName: "arrow.up.right").foregroundStyle(Nucleus.secondaryText) }
            }
            .buttonStyle(NucleusRowButtonStyle())
        }
    }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
