import DeviceActivity
import ManagedSettings
import UserNotifications

/// The 8 h safety cap, enforced even if PlaceLock never runs. Every unlock starts a one-off
/// Device Activity schedule (`ShieldManager.startSessionCap`). The app stops it when apps lock
/// again and restarts it after a successful 8 h recheck. If it runs out first, the app didn't
/// get to recheck (no geofence event, never opened), so block the apps again here.
///
/// The app's state still says "unlocked" until its next launch, when the overdue recheck runs:
/// a fresh GPS fix that unblocks again if you're still there, or locks for real if not.
final class SessionCapMonitor: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == SharedStore.sessionCap, let selection = SharedStore.blockedSelection else { return }
        SharedStore.shield(selection)

        let content = UNMutableNotificationContent()
        content.title = "PlaceLock"
        content.body = SharedStore.capPlaceName.map {
            "Unblocked at \($0) for 8 hours, so apps are blocked again. Open PlaceLock if you're still there."
        } ?? "Unblocked for 8 hours, so apps are blocked again. Open PlaceLock if you're still at your place."
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "sessionCap", content: content, trigger: nil))
    }
}
