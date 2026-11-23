import Foundation
import os

/// Where the app saves its state: `SharedStore.defaults` (the App Group in Screen Time builds).
/// The first Screen Time launch copies everything saved by earlier builds in
/// `UserDefaults.standard` into the App Group, so switching builds keeps places and settings.
enum Storage {
    static let defaults: UserDefaults = {
        let shared = SharedStore.defaults
        #if SCREEN_TIME
        migrate(into: shared) // free builds use `.standard` (or a geofence scenario's own store)
        #endif
        return shared
    }()

    /// Reads `key` with `decode` (a `SavedData` function). If some of it can't be read, logs that
    /// and copies the original under "unreadable.<key>" before the app saves over it, so what
    /// was lost can still be recovered. Only the first damaged copy is kept. `log` is the
    /// category to report it in (`Log.sync` for the sync engine's own state).
    static func load<T>(_ key: String, in defaults: UserDefaults = Storage.defaults, log: Logger = Log.app,
                        _ decode: (Any?) -> SavedData.Outcome<T>) -> SavedData.Outcome<T> {
        let stored = defaults.object(forKey: key)
        let outcome = decode(stored)
        guard outcome.lostSomething, let stored else { return outcome }
        if case .partial(_, let dropped) = outcome {
            log.error("Saved \(key, privacy: .public): \(dropped) item(s) couldn't be read and were set aside")
        } else {
            log.error("Saved \(key, privacy: .public) couldn't be read and was set aside")
        }
        let backupKey = "unreadable.\(key)"
        if defaults.object(forKey: backupKey) == nil { defaults.set(stored, forKey: backupKey) }
        return outcome
    }

    #if SCREEN_TIME
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
    #endif
}
