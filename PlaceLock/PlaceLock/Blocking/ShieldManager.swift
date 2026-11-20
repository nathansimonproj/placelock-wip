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

    /// Clears the 8 h cap's Device Activity schedule left by builds before 2026-11-19, so it can't
    /// fire and block apps again. PlaceLock no longer uses Device Activity for anything else.
    static func stopLegacySessionCap() {
        DeviceActivityCenter().stopMonitoring()
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


    static func stopLegacySessionCap() {}
#endif
}
