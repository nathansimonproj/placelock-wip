import CoreLocation
import FamilyControls
import Foundation
import Testing
@testable import PlaceLock

/// The 24 h delay on new places and on moving or enlarging one.
struct PlaceRulesTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let gym = Place(name: "Gym", latitude: 47.6537, longitude: -122.3012, radius: 150)
    let day = PlaceRules.changeDelay

    // MARK: Adding

    @Test func newPlaceDuringSetupIsActiveRightAway() {
        let added = PlaceRules.added(gym, inSetup: true, now: now)
        #expect(added.activeAfter == nil)
        #expect(added.isActive(at: now))
    }

    @Test func newPlaceAfterSetupWaits24Hours() {
        let added = PlaceRules.added(gym, inSetup: false, now: now)
        #expect(added.activeAfter == now.addingTimeInterval(day))
        #expect(!added.isActive(at: now.addingTimeInterval(day - 1)))
        #expect(added.isActive(at: now.addingTimeInterval(day)))
    }

    // MARK: Editing

    func edit(_ place: Place, name: String = "Gym", lat: Double? = nil, lon: Double? = nil,
              radius: Double? = nil, inSetup: Bool = false) -> (Place, PlaceRules.EditResult) {
        PlaceRules.edited(place, name: name, address: nil,
                          center: CLLocationCoordinate2D(latitude: lat ?? place.latitude, longitude: lon ?? place.longitude),
                          radius: radius ?? place.radius, inSetup: inSetup, now: now)
    }

    @Test func renameAppliesRightAway() {
        let (place, result) = edit(gym, name: "IMA")
        #expect(place.name == "IMA")
        #expect(result == .unchangedArea)
    }

    @Test func shrinkingAppliesRightAway() {
        let (place, result) = edit(gym, radius: 100)
        #expect(result == .appliedNow)
        #expect(place.radius == 100)
    }

    @Test func enlargingWaits() {
        let (place, result) = edit(gym, radius: 300)
        #expect(result == .pending(until: now.addingTimeInterval(day)))
        #expect(place.radius == 150) // the current circle keeps working
        #expect(place.pendingChange?.radius == 300)
    }

    @Test func movingFarWaits() {
        let (place, result) = edit(gym, lat: 47.6634, lon: -122.3139) // to The M
        #expect(result == .pending(until: now.addingTimeInterval(day)))
        #expect(place.latitude == gym.latitude)
    }

    @Test func enlargingDuringSetupAppliesRightAway() {
        let (place, result) = edit(gym, radius: 300, inSetup: true)
        #expect(result == .appliedNow)
        #expect(place.radius == 300)
    }

    @Test func editingAPlaceStillInItsDelayAppliesRightAway() {
        var waiting = gym
        waiting.activeAfter = now.addingTimeInterval(3600)
        let (place, result) = edit(waiting, radius: 400)
        #expect(result == .appliedNow)
        #expect(place.radius == 400)
        #expect(place.activeAfter == waiting.activeAfter) // the original 24 h still stands
    }

    @Test func containsAcceptsOnlyCirclesInside() {
        #expect(gym.contains(center: gym.coordinate, radius: 150))
        #expect(gym.contains(center: gym.coordinate, radius: 100))
        #expect(!gym.contains(center: gym.coordinate, radius: 151.5))
        // ~111 m north with a 50 m radius reaches 161 m from the center: outside.
        #expect(!gym.contains(center: .init(latitude: gym.latitude + 0.001, longitude: gym.longitude), radius: 50))
    }

    // MARK: Applying due changes

    @Test func nothingDueReturnsNil() {
        var waiting = gym
        waiting.activeAfter = now.addingTimeInterval(10)
        #expect(PlaceRules.applyingDue([waiting], now: now) == nil)
    }

    @Test func duePlaceTurnsOn() {
        var waiting = gym
        waiting.activeAfter = now.addingTimeInterval(-1)
        let updated = PlaceRules.applyingDue([waiting], now: now)
        #expect(updated?.first?.activeAfter == nil)
    }

    @Test func dueAreaChangeIsApplied() {
        let (pending, _) = edit(gym, radius: 300)
        let updated = PlaceRules.applyingDue([pending], now: now.addingTimeInterval(day))
        #expect(updated?.first?.radius == 300)
        #expect(updated?.first?.pendingChange == nil)
    }

    @Test func skippingDelaysAppliesEverything() {
        var waiting = PlaceRules.added(gym, inSetup: false, now: now)
        waiting = edit(waiting, radius: 120).0
        let (moved, _) = edit(gym, radius: 300)
        let skipped = PlaceRules.skippingDelays([waiting, moved])
        #expect(skipped.allSatisfy { $0.activeAfter == nil && $0.pendingChange == nil })
        #expect(skipped[1].radius == 300)
    }
}

/// The 24 h delay on removing blocked apps.
struct BlockRulesTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let day = BlockRules.removalDelay

    func list(_ apps: [String], pending: [String: Date] = [:]) -> BlockList {
        var list = BlockList()
        list.simulatedApps = apps
        list.pendingRemovals.simulated = pending
        return list
    }

    @Test func removalWaits24Hours() {
        let old = list(["Instagram", "TikTok"])
        let result = BlockRules.holdingRemovals(old: old, new: list(["TikTok"]), delayed: true, now: now)
        #expect(result.simulatedApps == ["Instagram", "TikTok"]) // still blocked, order kept
        #expect(result.pendingRemovals.simulated["Instagram"] == now.addingTimeInterval(day))
    }

    @Test func removalDuringSetupIsInstant() {
        let old = list(["Instagram", "TikTok"])
        let result = BlockRules.holdingRemovals(old: old, new: list(["TikTok"]), delayed: false, now: now)
        #expect(result.simulatedApps == ["TikTok"])
        #expect(result.pendingRemovals.simulated.isEmpty)
    }

    @Test func addingIsAlwaysInstant() {
        let result = BlockRules.holdingRemovals(old: list(["TikTok"]), new: list(["TikTok", "YouTube"]),
                                                delayed: true, now: now)
        #expect(result.simulatedApps == ["TikTok", "YouTube"])
        #expect(result.pendingRemovals.simulated.isEmpty)
    }

    @Test func removingAgainKeepsTheOriginalDate() {
        let first = now.addingTimeInterval(day)
        let old = list(["Instagram"], pending: ["Instagram": first])
        let new = list([], pending: ["Instagram": first])
        let result = BlockRules.holdingRemovals(old: old, new: new, delayed: true, now: now.addingTimeInterval(3600))
        #expect(result.pendingRemovals.simulated["Instagram"] == first)
    }

    @Test func keepBlockedCancelsTheRemoval() {
        let old = list(["Instagram"], pending: ["Instagram": now.addingTimeInterval(day)])
        let new = list(["Instagram"]) // pending entry cleared, app untouched
        let result = BlockRules.holdingRemovals(old: old, new: new, delayed: true, now: now)
        #expect(result.simulatedApps == ["Instagram"])
        #expect(result.pendingRemovals.simulated.isEmpty)
    }

    @Test func dueRemovalsComeOff() {
        let waiting = list(["Instagram", "TikTok"], pending: ["Instagram": now])
        let result = BlockRules.applyingDueRemovals(waiting, now: now)
        #expect(result?.simulatedApps == ["TikTok"])
        #expect(result?.pendingRemovals.isEmpty == true)
    }

    @Test func removalsNotYetDueStay() {
        let waiting = list(["Instagram"], pending: ["Instagram": now.addingTimeInterval(1)])
        #expect(BlockRules.applyingDueRemovals(waiting, now: now) == nil)
    }

    @Test func setVersionHoldsRemovedTokens() {
        var pending: [Int: Date] = [:]
        let kept = BlockRules.hold(old: [1, 2, 3], new: [1], pending: &pending, delayed: true, now: now)
        #expect(kept == [1, 2, 3])
        #expect(Set(pending.keys) == [2, 3])
    }

    @Test func oldSaveWithoutPendingRemovalsStillLoads() throws {
        // Block lists saved before pendingRemovals existed must not reset to empty.
        struct OldBlockList: Encodable {
            var selection = FamilyActivitySelection()
            var simulatedApps = ["Instagram", "TikTok"]
        }
        let data = try JSONEncoder().encode(OldBlockList())
        let decoded = try JSONDecoder().decode(BlockList.self, from: data)
        #expect(decoded.simulatedApps == ["Instagram", "TikTok"])
        #expect(decoded.pendingRemovals.isEmpty)
    }
}
