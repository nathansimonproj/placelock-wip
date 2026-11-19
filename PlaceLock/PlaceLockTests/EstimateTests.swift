import CoreLocation
import Foundation
import Testing
@testable import PlaceLock

/// The block screen's "Estimated @ … · 2 min ago" line and how it names a spot.
struct EstimateTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let gym = Place(name: "Gym", latitude: 47.6537, longitude: -122.3012, radius: 150)
    let home = Place(name: "Home", latitude: 47.6634, longitude: -122.3139, radius: 100)

    /// About `meters` north of the gym's center.
    func northOfGym(_ meters: Double) -> CLLocation {
        CLLocation(latitude: gym.latitude + meters / 111_000, longitude: gym.longitude)
    }

    // MARK: Naming the spot

    @Test func insideAPlaceUsesItsName() {
        #expect(EstimateRules.label(at: northOfGym(50), places: [gym, home], mapName: "Some Street") == "Gym")
    }

    @Test func outsideUsesTheMapName() {
        #expect(EstimateRules.label(at: northOfGym(600), places: [gym, home], mapName: "Suzzallo Library")
            == "Suzzallo Library")
    }

    @Test func withoutAMapNameUsesDistanceToNearestPlace() {
        #expect(EstimateRules.label(at: northOfGym(550), places: [gym, home], mapName: nil) == "550 m from Gym")
        #expect(EstimateRules.label(at: northOfGym(550), places: [gym], mapName: "  ") == "550 m from Gym")
    }

    @Test func nothingToSayWithNoPlacesAndNoMapName() {
        #expect(EstimateRules.label(at: northOfGym(550), places: [], mapName: nil) == nil)
    }

    @Test func distancesRound() {
        #expect(EstimateRules.distance(83) == "80 m")
        #expect(EstimateRules.distance(412) == "400 m")
        #expect(EstimateRules.distance(1234) == "1.2 km")
        #expect(EstimateRules.distance(12_400) == "12 km")
    }

    // MARK: The block screen line

    @Test func lineShowsAge() {
        let est = SharedStore.Estimate(label: "Suzzallo Library", at: now)
        #expect(Brand.estimated(est, now: now.addingTimeInterval(20)) == "Estimated @ Suzzallo Library · just now")
        #expect(Brand.estimated(est, now: now.addingTimeInterval(150)) == "Estimated @ Suzzallo Library · 2 min ago")
        #expect(Brand.estimated(est, now: now.addingTimeInterval(3 * 3600 + 5)) == "Estimated @ Suzzallo Library · 3 h ago")
    }

    @Test func staleOrMissingEstimateIsLeftOut() {
        let old = SharedStore.Estimate(label: "Gym", at: now.addingTimeInterval(-25 * 3600))
        #expect(Brand.shieldSubtitle(estimate: old, places: ["Gym", "Home"], now: now) == "Opens at Gym or Home.")
        #expect(Brand.shieldSubtitle(estimate: nil, places: ["Gym"], now: now) == "Opens at Gym.")
    }

    @Test func subtitleHasBothLines() {
        let est = SharedStore.Estimate(label: "Gym", at: now.addingTimeInterval(-120))
        #expect(Brand.shieldSubtitle(estimate: est, places: ["Gym", "Field", "Home"], now: now)
            == "Estimated @ Gym · 2 min ago\nOpens at Gym, Field or Home.")
    }
}
