import Foundation
import NucleusUI
import Observation

enum ViewMode: String, CaseIterable {
    case grid, list

    var title: String {
        switch self {
        case .grid: String(localized: "Grid")
        case .list: String(localized: "List")
        }
    }
}

/// Device-local preferences (UserDefaults). None of these sync.
@MainActor
@Observable
final class Preferences {
    private let defaults: UserDefaults

    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    /// The web's `orbit:viewMode`.
    var viewMode: ViewMode { didSet { defaults.set(viewMode.rawValue, forKey: "viewMode") } }
    var appLock: Bool { didSet { defaults.set(appLock, forKey: "appLock") } }
    var shakeToReport: Bool { didSet { defaults.set(shakeToReport, forKey: "shakeToReport") } }
    var hasSeenWelcome: Bool { didSet { defaults.set(hasSeenWelcome, forKey: "hasSeenWelcome") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "appearance": AppearanceMode.dark.rawValue,
            "viewMode": ViewMode.grid.rawValue,
            "appLock": false,
            "shakeToReport": true,
            "hasSeenWelcome": false,
        ])
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .dark
        viewMode = ViewMode(rawValue: defaults.string(forKey: "viewMode") ?? "") ?? .grid
        appLock = defaults.bool(forKey: "appLock")
        shakeToReport = defaults.bool(forKey: "shakeToReport")
        hasSeenWelcome = defaults.bool(forKey: "hasSeenWelcome")
    }
}
