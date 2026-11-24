import SwiftUI
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var protectedDataObserver: NSObjectProtocol?

    // Runs on background relaunches too (geofence enter/exit), unlike SwiftUI views.
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if application.isProtectedDataAvailable {
            startUp()
        } else {
            // After a restart, before the first unlock, saved data can't be read: AppModel would
            // load nothing and save that over your places, setup window and blocked apps. iOS
            // doesn't watch places until the first unlock anyway. So don't touch AppModel,
            // SyncEngine or Storage until then.
            Log.app.notice("Launched before first unlock; waiting for protected data")
            protectedDataObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let observer = self.protectedDataObserver else { return }
                    NotificationCenter.default.removeObserver(observer)
                    self.protectedDataObserver = nil
                    Log.app.notice("Protected data available; starting")
                    self.startUp()
                }
            }
        }
        return true
    }

    private func startUp() {
        Task { @MainActor in await AppModel.shared.startUp() } // startUp runs once per launch
    }

    // Show the "apps unblocked" / "apps blocked" banners even if the app is open.
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
                AppModel.shared.cameToFront()
                Task {
                    await AppModel.shared.clearOldNotices(all: true) // the app shows the same thing
                    await AppModel.shared.reconcile()
                }
                SyncEngine.shared.requestSync()
            }
        }
    }
}
