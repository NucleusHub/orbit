import NucleusUI
import SwiftUI
import UIKit

/// The lock screen and the app-switcher shield in a window of their own, above every sheet and
/// cover: SwiftUI presents those over the root view, so an overlay there would sit underneath.
@MainActor
final class LockWindow {
    static let shared = LockWindow()
    private var window: UIWindow?

    func show(lock: AppLock, colorScheme: ColorScheme?) {
        if window == nil {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
            let w = UIWindow(windowScene: scene)
            w.windowLevel = .alert + 1
            window = w
        }
        let host = UIHostingController(rootView: LockCover().environment(lock).preferredColorScheme(colorScheme).nucleusAccentTint())
        window?.rootViewController = host
        window?.isHidden = false
    }

    func hide() {
        window?.isHidden = true
        window = nil
    }
}

/// The lock while locked, otherwise the plain shield.
private struct LockCover: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        if lock.isLocked { LockScreen() } else { PrivacyShield() }
    }
}
