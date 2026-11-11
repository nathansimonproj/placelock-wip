import FamilyControls
import ManagedSettings

/// Applies or clears the block on the user's chosen apps.
///
/// Built with `SCREEN_TIME` (paid team + Family Controls entitlement, see project.yml): real Screen
/// Time shields. Otherwise a stand-in that only logs and reports what would be blocked, so the rest
/// of the app can be built and tested on a free account.
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
        let s = list.selection
        store.shield.applications = s.applicationTokens.isEmpty ? nil : s.applicationTokens
        store.shield.applicationCategories = s.categoryTokens.isEmpty ? nil : .specific(s.categoryTokens)
        store.shield.webDomains = s.webDomainTokens.isEmpty ? nil : s.webDomainTokens
    }

    static func unlock() {
        store.clearAllSettings()
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
#endif
}
