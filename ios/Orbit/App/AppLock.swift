import LocalAuthentication
import NucleusUI
import Observation
import SwiftUI

@MainActor
@Observable
final class AppLock {
    private(set) var isLocked = false
    private(set) var isAuthenticating = false
    @ObservationIgnored private var backgroundedAt: Date?

    /// Re-lock only after a real absence, so a quick glance at another app doesn't nag.
    static let gracePeriod: TimeInterval = 30

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return String(localized: "Passcode")
        }
    }

    var biometryIcon: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "faceid"
        }
    }

    func lockOnLaunch(enabled: Bool) {
        if enabled { isLocked = true }
    }

    func didEnterBackground() {
        backgroundedAt = Date()
    }

    func willEnterForeground(enabled: Bool) {
        guard enabled, let backgroundedAt else { return }
        if Date().timeIntervalSince(backgroundedAt) > Self.gracePeriod { isLocked = true }
        self.backgroundedAt = nil
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Unlock Orbit"))) ?? false
        if ok {
            withAnimation(NucleusMotion.quick) { isLocked = false }
        }
    }

    /// Confirms the owner before turning the lock on or revealing secrets.
    func confirmOwner(reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

struct LockScreen: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        ZStack {
            NucleusBackground()
            VStack(spacing: 18) {
                AppGlyph(size: 88)
                Text("Orbit is locked")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Nucleus.primaryText)
                Text("Your files stay private until you unlock.")
                    .font(.system(size: 15))
                    .foregroundStyle(Nucleus.secondaryText)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Unlock with \(lock.biometryName)", systemImage: lock.biometryIcon)
                }
                .buttonStyle(NucleusPrimaryButtonStyle())
                .padding(.top, 12)
                .frame(maxWidth: 320)
            }
            .padding(32)
        }
        .task { await lock.unlock() }
    }
}

/// Covers the UI in the app switcher so tasks don't show in the snapshot.
struct PrivacyShield: View {
    var body: some View {
        ZStack {
            NucleusBackground()
            AppGlyph(size: 96)
        }
        .transition(.opacity)
    }
}
