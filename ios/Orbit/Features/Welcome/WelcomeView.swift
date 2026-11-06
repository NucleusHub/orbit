import NucleusUI
import SwiftUI

struct WelcomeView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(NucleusID.self) private var auth
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NucleusWelcome(
            title: "Orbit",
            subtitle: "Your files, on your own Nucleus server.",
            points: [
                WelcomePoint("folder.fill", tint: .indigo, title: "Everything in one place", message: "Browse, search and preview every file and folder you keep in Orbit."),
                WelcomePoint("photo.on.rectangle.angled", tint: .emerald, title: "Photos in, converted", message: "Upload straight from Photos. Videos and HEIC photos are converted so they play everywhere."),
                WelcomePoint("lock.fill", tint: .amber, title: "Private folders", message: "Put a password on a folder or a single file."),
                WelcomePoint("person.2.fill", tint: .violet, title: "Shared with your groups", message: "Group folders show up next to your own."),
            ],
            primary: auth.isSignedIn ? "Get started" : "Sign in with Nucleus ID",
            onStart: {
                Haptics.tap()
                preferences.hasSeenWelcome = true
                if auth.isSignedIn || DebugLaunch.sampleData {
                    dismiss()
                } else {
                    // Swapping the sheet's item replaces Welcome with the sign-in sheet.
                    navigator.sheet = .signIn(nil)
                }
            },
            hero: {
                AppGlyph(size: 104)
            },
            footer: {
                if !auth.isSignedIn {
                    Button("Not now") {
                        Haptics.tap()
                        preferences.hasSeenWelcome = true
                        dismiss()
                    }
                    .buttonStyle(NucleusSecondaryButtonStyle())
                }
            }
        )
        .background(NucleusBackground())
    }
}

/// Orbit keeps files on a server, so there's nothing to show until someone signs in.
struct SignedOutHome: View {
    @Environment(NucleusID.self) private var auth
    @Environment(Navigator.self) private var navigator

    var body: some View {
        ZStack {
            NucleusBackground()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    GlassCircleButton("gearshape") { navigator.open(.settings) }
                        .accessibilityLabel("Settings")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
                VStack(spacing: 18) {
                    AppGlyph(size: 88)
                    Text(verbatim: "Orbit")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Nucleus.primaryText)
                    Text("Sign in with your Nucleus ID to see the files on your server.")
                        .font(.system(size: 15))
                        .foregroundStyle(Nucleus.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button {
                        Haptics.tap()
                        navigator.present(.signIn(nil))
                    } label: {
                        HStack {
                            if auth.signingIn { ProgressView().tint(.white) }
                            Text("Sign in with Nucleus ID")
                        }
                    }
                    .buttonStyle(NucleusPrimaryButtonStyle())
                    .disabled(auth.signingIn)
                    .padding(.horizontal, 32)
                    .padding(.top, 6)
                    if let message = auth.error.map(SettingsView.message) {
                        Text(message).font(.system(size: 13)).foregroundStyle(Nucleus.danger)
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                    }
                }
                Spacer()
                Spacer()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
