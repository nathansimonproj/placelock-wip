import Foundation

/// Where the app saves its state: `SharedStore.defaults` (the App Group in Screen Time builds).
/// The first Screen Time launch copies everything saved by earlier builds in
/// `UserDefaults.standard` into the App Group, so switching builds keeps places and settings.
enum Storage {
    static let defaults: UserDefaults = {
        let shared = SharedStore.defaults
        migrate(into: shared)
        return shared
    }()

    private static let migratedKey = "movedToAppGroup"

    private static func migrate(into shared: UserDefaults) {
        guard shared !== UserDefaults.standard, !shared.bool(forKey: migratedKey),
              let bundleID = Bundle.main.bundleIdentifier,
              let old = UserDefaults.standard.persistentDomain(forName: bundleID) else { return }
        // Keys already in the group win: never overwrite newer data with older.
        for (key, value) in old where shared.object(forKey: key) == nil {
            shared.set(value, forKey: key)
        }
        shared.set(true, forKey: migratedKey)
        // The old copy stays in place, so going back to a free build still finds it.
        Log.app.info("Copied \(old.count) saved values into the App Group")
    }
}
