import SwiftUI
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    // Runs on background relaunches too (geofence enter/exit), unlike SwiftUI views.
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in await AppModel.shared.startUp() }
        return true
    }

    // Show the "unlocked" / "apps locked" banners even if the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
struct PlaceLockApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(AppModel.shared)
                .environmentObject(AppModel.shared.location)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await AppModel.shared.reconcile() }
                SyncEngine.shared.requestSync()
            }
        }
    }
}
