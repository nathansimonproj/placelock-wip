import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Applies or clears the block on the user's chosen apps.
///
/// Built with `SCREEN_TIME` (paid team + Family Controls entitlement, see project-paid.yml): real
/// Screen Time shields. Otherwise a stand-in that only logs and reports what would be blocked, so
/// the rest of the app can be built and tested on a free account.
enum ShieldManager {
    /// The 8 h cap's backstop fires this long after the app's own recheck is due, so a running
    /// app gets to confirm with GPS first and the extension only catches the case where it didn't.
    static let capGrace: TimeInterval = 5 * 60

#if SCREEN_TIME
    static let isSimulated = false
    private static let store = ManagedSettingsStore()

    static func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    static var isAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    static func lock(_ list: BlockList) {
        SharedStore.shield(list.selection, in: store)
    }

    static func unlock() {
        store.clearAllSettings()
    }

    /// Starts the safety cap for an unlock that began at `start`: if the app hasn't rechecked by
    /// `start + maxSession + capGrace`, the SessionCap extension blocks the apps again.
    /// Replaces any cap already running.
    static func startSessionCap(from start: Date, maxSession: TimeInterval, placeName: String) {
        let center = DeviceActivityCenter()
        center.stopMonitoring([SharedStore.sessionCap])
        SharedStore.capPlaceName = placeName
        let calendar = Calendar.current
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(parts, from: start),
            intervalEnd: calendar.dateComponents(parts, from: start.addingTimeInterval(maxSession + capGrace)),
            repeats: false)
        do {
            try center.startMonitoring(SharedStore.sessionCap, during: schedule)
        } catch {
            Log.app.error("Couldn't start the 8 h cap: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func stopSessionCap() {
        DeviceActivityCenter().stopMonitoring([SharedStore.sessionCap])
        SharedStore.capPlaceName = nil
    }
#else
    static let isSimulated = true

    static func requestAuthorization() async throws {}

    static var isAuthorized: Bool { true }

    static func lock(_ list: BlockList) {
        Log.app.info("[simulated] would block: \(list.summary, privacy: .public)")
    }

    static func unlock() {
        Log.app.info("[simulated] would unblock all apps")
    }

    static func startSessionCap(from start: Date, maxSession: TimeInterval, placeName: String) {}

    static func stopSessionCap() {}
#endif
}
