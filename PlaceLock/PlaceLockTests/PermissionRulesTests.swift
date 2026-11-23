import CoreLocation
import Testing
import UserNotifications
@testable import PlaceLock

/// Home's fix banner when a permission is missing: what it says and where its button goes.
struct PermissionRulesTests {
    private func problem(_ screenTime: AppModel.ScreenTimeAccess = .approved,
                         _ location: CLAuthorizationStatus = .authorizedAlways,
                         precise: Bool = true) -> PermissionRules.Problem? {
        PermissionRules.problem(screenTime: screenTime, location: location, precise: precise)
    }

    @Test func nothingToFixWithAlwaysAndPrecise() {
        #expect(problem() == nil)
    }

    @Test func locationNeverAskedShowsTheLocationPrompt() {
        #expect(problem(.approved, .notDetermined) == .init(text: "Location access needed", fix: .askLocation))
    }

    @Test(arguments: [CLAuthorizationStatus.denied, .restricted])
    func locationDeniedOpensSettings(_ status: CLAuthorizationStatus) {
        #expect(problem(.approved, status) == .init(text: "Location access is off", fix: .openSettings))
    }

    @Test func whileUsingOpensSettings() {
        #expect(problem(.approved, .authorizedWhenInUse) == .init(text: "Location isn't set to Always", fix: .openSettings))
    }

    @Test func whileUsingIsFixedBeforePrecise() {
        #expect(problem(.approved, .authorizedWhenInUse, precise: false)?.text == "Location isn't set to Always")
    }

    @Test func preciseOffOpensSettings() {
        #expect(problem(.approved, .authorizedAlways, precise: false) == .init(text: "Precise Location is off", fix: .openSettings))
    }

    @Test func screenTimeComesFirst() {
        #expect(problem(.notYet, .denied) == .init(text: "Screen Time access needed", fix: .askScreenTime))
        #expect(problem(.turnedOff, .authorizedAlways) == .init(text: "Blocking is off", fix: .askScreenTime))
    }

    @Test func onlyDeniedNotificationsAreFlagged() {
        #expect(PermissionRules.notificationsOff(.denied))
        #expect(!PermissionRules.notificationsOff(.notDetermined))
        #expect(!PermissionRules.notificationsOff(.authorized))
        #expect(!PermissionRules.notificationsOff(.provisional))
    }
}
