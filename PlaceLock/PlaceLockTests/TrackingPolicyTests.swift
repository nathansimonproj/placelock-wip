import CoreLocation
import Foundation
import Testing
@testable import PlaceLock

/// How hard Cove tracks: closely only near an edge, or inside when you might be leaving.
struct TrackingPolicyTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func mode(edge: Double?, radius: Double = 100, inside: Bool = false, stationary: Bool = false,
              resumed: Bool = false, speed: Double = -1, exitHint: Bool = false, burstAgo: TimeInterval? = nil,
              lowPower: Bool = false, previous: TrackingPolicy.Mode = .dormant) -> TrackingPolicy.Mode {
        TrackingPolicy.mode(.init(distanceToEdge: edge, radius: radius, inside: inside, stationary: stationary,
                                  resumed: resumed, speed: speed, exitHint: exitHint,
                                  burstStartedAt: burstAgo.map { now.addingTimeInterval(-$0) },
                                  lowPower: lowPower, previous: previous, now: now))
    }

    // MARK: Outside

    @Test func farFromEveryPlaceIsDormant() {
        #expect(mode(edge: 5_000) == .dormant)
        #expect(mode(edge: nil) == .dormant)
    }

    @Test func withinAKilometerIsApproach() {
        #expect(mode(edge: 800) == .approach)
    }

    @Test func nearAnEdgeIsEdge() {
        #expect(mode(edge: 100) == .edge)
        #expect(mode(edge: -5) == .edge) // inside the circle but not yet confirmed inside
    }

    @Test func modesHoldOnALittleFarther() {
        #expect(mode(edge: 180) == .approach)
        #expect(mode(edge: 180, previous: .edge) == .edge)
        #expect(mode(edge: 1_030) == .dormant)
        #expect(mode(edge: 1_030, previous: .approach) == .approach)
    }

    @Test func lowPowerDropsALevel() {
        #expect(mode(edge: 100, lowPower: true) == .approach)
        #expect(mode(edge: 800, lowPower: true) == .dormant)
    }

    // MARK: Inside

    @Test func sittingStillAtASmallPlaceIsInsideNotEdge() {
        // A 50 m place is all near the edge; sitting still must not keep GPS on.
        #expect(mode(edge: -10, radius: 50, inside: true, stationary: true) == .inside)
        #expect(mode(edge: -30, radius: 100, inside: true, stationary: true) == .inside)
    }

    @Test func movingAwayFromTheEdgeStaysInside() {
        // 60 m in from the edge of a 100 m place: outside its 40 m band.
        #expect(mode(edge: -60, radius: 100, inside: true) == .inside)
    }

    @Test func signsOfLeavingStartABurst() {
        #expect(mode(edge: -30, radius: 100, inside: true) == .burst) // in the 40 m band
        #expect(mode(edge: -60, radius: 100, inside: true, resumed: true) == .burst)
        #expect(mode(edge: -60, radius: 100, inside: true, speed: 3) == .burst)
        #expect(mode(edge: -60, radius: 100, inside: true, exitHint: true) == .burst)
    }

    @Test func aBurstEndsWhenStillOrAfterTwoMinutes() {
        #expect(mode(edge: -60, radius: 100, inside: true, burstAgo: 30) == .burst)
        #expect(mode(edge: -60, radius: 100, inside: true, stationary: true, burstAgo: 30) == .inside)
        #expect(mode(edge: -60, radius: 100, inside: true, burstAgo: 130) == .inside)
    }

    @Test func theEdgeBandScalesWithThePlace() {
        #expect(TrackingPolicy.edgeBand(radius: 50) == 25)
        #expect(TrackingPolicy.edgeBand(radius: 100) == 40)
        #expect(TrackingPolicy.edgeBand(radius: 300) == 120)
        #expect(TrackingPolicy.edgeBand(radius: 500) == 150)
    }

    // MARK: Settings

    @Test func settingsMatchTheModes() {
        #expect(!TrackingPolicy.settings(for: .dormant, lowPower: false).running)
        #expect(TrackingPolicy.settings(for: .edge, lowPower: false).accuracy == kCLLocationAccuracyBest)
        #expect(TrackingPolicy.settings(for: .inside, lowPower: false).accuracy == kCLLocationAccuracyHundredMeters)
        #expect(TrackingPolicy.settings(for: .burst, lowPower: false).accuracy == kCLLocationAccuracyBest)
        #expect(TrackingPolicy.settings(for: .burst, lowPower: true).accuracy == kCLLocationAccuracyHundredMeters)
    }
}
