import FamilyControls
import Foundation
import ManagedSettings

/// What the app shares with its Screen Time extension (the block screen).
/// Compiled into the app and the extension, so keep it small and free of app types.
///
/// Built with `SCREEN_TIME` the data lives in the App Group, which the extensions can read.
/// Without it (free team, no App Group entitlement) it's plain `UserDefaults.standard`.
enum SharedStore {
    static let appGroup = "group.com.nsimon.PlaceLock"

    static let defaults: UserDefaults = {
        #if SCREEN_TIME
        UserDefaults(suiteName: appGroup) ?? .standard
        #else
        Scenario.defaults ?? .standard // a separate store while running a geofence scenario (Debug)
        #endif
    }()

    private enum Keys {
        static let allowedPlaces = "shared.allowedPlaceNames"
        static let estimate = "shared.estimate"
    }

    /// Where the app last thought you were, for the block screen's "Estimated @" line.
    /// The block screen can't read location itself.
    struct Estimate: Codable, Equatable {
        /// A place name ("Gym"), a map name ("Suzzallo Library"), or "400 m from Gym".
        var label: String
        var at: Date
    }

    static var estimate: Estimate? {
        get { defaults.data(forKey: Keys.estimate).flatMap { try? JSONDecoder().decode(Estimate.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.estimate) }
    }

    /// Names of the places that can unblock apps right now, for the block screen.
    static var allowedPlaceNames: [String] {
        get { defaults.stringArray(forKey: Keys.allowedPlaces) ?? [] }
        set { defaults.set(newValue, forKey: Keys.allowedPlaces) }
    }

    /// Turns on shields for `selection`: its apps, its categories' apps and websites, and its websites. The app and the extensions share the default store.
    static func shield(_ selection: FamilyActivitySelection, in store: ManagedSettingsStore = ManagedSettingsStore()) {
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        // A picked category blocks its websites too, so the browser isn't an easy way around it.
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }
}
