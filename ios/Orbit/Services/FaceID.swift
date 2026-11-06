import LocalAuthentication

enum BiometricOutcome: Equatable {
    case success
    /// The person chose to type the item's Orbit password instead.
    case usePassword
    case cancelled
    case failed(String)
}

protocol Authenticator: Sendable {
    func authenticate(reason: String, strict: Bool, passwordFallback: Bool) async -> BiometricOutcome
}

/// Face ID through LocalAuthentication. Strict allows biometrics only: no passcode, no password, and after
/// too many failures iOS keeps Face ID locked until the phone is unlocked with its passcode.
struct LocalAuthenticator: Authenticator {
    func authenticate(reason: String, strict: Bool, passwordFallback: Bool) async -> BiometricOutcome {
        let context = LAContext()
        let policy: LAPolicy
        if strict {
            policy = .deviceOwnerAuthenticationWithBiometrics
            context.localizedFallbackTitle = ""
        } else if passwordFallback {
            policy = .deviceOwnerAuthenticationWithBiometrics
            context.localizedFallbackTitle = String(localized: "Use Orbit password")
        } else {
            policy = .deviceOwnerAuthentication
        }
        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else {
            if !strict, passwordFallback { return .usePassword }
            return .failed(Self.message(for: error))
        }
        do {
            return try await context.evaluatePolicy(policy, localizedReason: reason) ? .success : .cancelled
        } catch let e as LAError {
            switch e.code {
            case .userFallback: return .usePassword
            case .userCancel, .appCancel, .systemCancel: return .cancelled
            default: return .failed(Self.message(for: e as NSError))
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func message(for error: NSError?) -> String {
        switch (error as? LAError)?.code ?? LAError.Code(rawValue: error?.code ?? 0) {
        case .biometryLockout:
            String(localized: "Face ID is locked after too many tries. Unlock your iPhone with its passcode, then try again.")
        case .biometryNotEnrolled:
            String(localized: "Face ID isn't set up on this iPhone, so this can't be opened here.")
        case .biometryNotAvailable:
            String(localized: "Face ID isn't available, so this can't be opened here.")
        case .authenticationFailed:
            String(localized: "Face ID didn't recognize you.")
        default:
            error?.localizedDescription ?? String(localized: "Face ID didn't recognize you.")
        }
    }
}

/// `-faceID pass|fail` for UI tests and screenshots, where the simulator has no face.
struct ScriptedAuthenticator: Authenticator {
    let passes: Bool

    func authenticate(reason: String, strict: Bool, passwordFallback: Bool) async -> BiometricOutcome {
        passes ? .success : .failed(String(localized: "Face ID didn't recognize you."))
    }
}
