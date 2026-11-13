import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// What the app shares with its Screen Time extensions (block screen, 8 h cap).
/// Compiled into the app and both extensions, so keep it small and free of app types.
///
/// Built with `SCREEN_TIME` the data lives in the App Group, which the extensions can read.
/// Without it (free team, no App Group entitlement) it's plain `UserDefaults.standard`.
enum SharedStore {
    static let appGroup = "group.com.nsimon.PlaceLock"

    static let defaults: UserDefaults = {
        #if SCREEN_TIME
        UserDefaults(suiteName: appGroup) ?? .standard
        #else
        .standard
        #endif
    }()

    /// The Device Activity schedule behind the 8 h safety cap.
    static let sessionCap = DeviceActivityName("sessionCap")

    private enum Keys {
        static let allowedPlaces = "shared.allowedPlaceNames"
        static let selection = "shared.blockedSelection"
        static let capPlace = "shared.capPlaceName"
    }

    /// Names of the places that can unblock apps right now, for the block screen.
    static var allowedPlaceNames: [String] {
        get { defaults.stringArray(forKey: Keys.allowedPlaces) ?? [] }
        set { defaults.set(newValue, forKey: Keys.allowedPlaces) }
    }

    /// What to block, so the 8 h cap can turn blocking back on without the app.
    static var blockedSelection: FamilyActivitySelection? {
        get {
            defaults.data(forKey: Keys.selection)
                .flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
        }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.selection) }
    }

    /// The place of the unlock the 8 h cap is timing, for its notification.
    static var capPlaceName: String? {
        get { defaults.string(forKey: Keys.capPlace) }
        set { defaults.set(newValue, forKey: Keys.capPlace) }
    }

    /// Turns on shields for `selection`. The app and the extensions share the default store.
    static func shield(_ selection: FamilyActivitySelection, in store: ManagedSettingsStore = ManagedSettingsStore()) {
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }
}
