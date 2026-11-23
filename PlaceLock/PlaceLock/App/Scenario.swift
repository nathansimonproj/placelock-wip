import Foundation

/// Geofence scenarios (`scripts/geofence-scenario.py`, the `/geofence-scenario` skill).
///
/// Launched with `-scenario <name>` (Debug, free build), the app keeps everything in its own
/// settings store instead of `UserDefaults.standard`, so the places and history you use in the
/// Simulator are left alone, and backup is off (`SyncEngine.shared` gets no backend).
/// `-scenarioPlaces <base64 JSON>` on a run's first launch wipes that store and loads the places
/// (an array in `Place`'s Codable form). Launches without it keep the store as the run left it.
enum Scenario {
    #if DEBUG && !SCREEN_TIME
    static let name = UserDefaults.standard.string(forKey: "scenario")
    static var isActive: Bool { name != nil }

    private static let suiteName = "com.nsimon.PlaceLock.scenario"

    /// The scenario's store, or nil when not running a scenario.
    static let defaults: UserDefaults? = {
        guard let name, let store = UserDefaults(suiteName: suiteName) else { return nil }
        if let encoded = UserDefaults.standard.string(forKey: "scenarioPlaces") {
            store.removePersistentDomain(forName: suiteName)
            // Decode and re-encode, so a fixture that doesn't match `Place` fails loudly here
            // (the runner checks the "Launch: N places" line) rather than loading nothing.
            do {
                let places = try JSONDecoder().decode([Place].self, from: Data(base64Encoded: encoded) ?? Data())
                store.set(try JSONEncoder().encode(places), forKey: "places") // AppModel.Keys.places
                store.set(true, forKey: "onboarded")                         // Keys.onboarded
                store.set(true, forKey: "seededDefaultPlaces")               // Keys.seeded
                Log.app.info("Scenario \(name, privacy: .public): loaded \(places.count) places")
            } catch {
                Log.app.error("Scenario \(name, privacy: .public): places didn't load: \(error.localizedDescription, privacy: .public)")
            }
        }
        return store
    }()
    #else
    static let isActive = false
    static let defaults: UserDefaults? = nil
    #endif
}
