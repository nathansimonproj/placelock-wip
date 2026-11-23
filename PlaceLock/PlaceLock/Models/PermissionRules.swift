import CoreLocation
import UserNotifications

// MARK: - Missing permissions

/// What Home's fix banner says when places can't unlock apps, and what its button does. Apps
/// stay blocked in every one of these cases (`LockRules` locks without Always and Precise);
/// this only decides how to tell you and how to fix it.
enum PermissionRules {
    enum Fix: Equatable {
        /// Show iOS's Screen Time prompt. It can be shown again after access was turned off.
        case askScreenTime
        /// Show iOS's location prompt. iOS only shows it before the first answer.
        case askLocation
        /// iOS won't ask again, so open Spots in the Settings app.
        case openSettings
    }

    struct Problem: Equatable {
        let text: String
        let fix: Fix
    }

    /// The one thing to fix first, or nil when nothing stops places from unlocking apps.
    /// Screen Time comes first: without it nothing is blocked at all.
    static func problem(screenTime: AppModel.ScreenTimeAccess, location: CLAuthorizationStatus,
                        precise: Bool) -> Problem? {
        switch screenTime {
        case .notYet: return Problem(text: "Screen Time access needed", fix: .askScreenTime)
        case .turnedOff: return Problem(text: "Blocking is off", fix: .askScreenTime)
        case .approved: break
        }
        switch location {
        case .notDetermined:
            return Problem(text: "Location access needed", fix: .askLocation)
        case .authorizedWhenInUse:
            // Always first: Precise alone wouldn't be enough.
            return Problem(text: "Location isn't set to Always", fix: .openSettings)
        case .authorizedAlways:
            return precise ? nil : Problem(text: "Precise Location is off", fix: .openSettings)
        default: // denied, restricted (Screen Time or a profile), or Location Services off
            return Problem(text: "Location access is off", fix: .openSettings)
        }
    }

    /// Notifications were turned off in Settings (or declined at iOS's prompt). "Not now" during
    /// setup never asked iOS, so it isn't flagged.
    static func notificationsOff(_ status: UNAuthorizationStatus) -> Bool {
        status == .denied
    }
}
