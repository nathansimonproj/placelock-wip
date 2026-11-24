import Foundation
import Testing
@testable import PlaceLock

/// Inside or outside each place, from Cove's own fixes with iOS's events as a fallback.
struct PresenceRulesTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let gym = Place(name: "Gym", latitude: 47.6537, longitude: -122.3012, radius: 150)
    let home = Place(name: "Home", latitude: 47.6634, longitude: -122.3139, radius: 100)

    /// A fix `edge` meters north of the place's edge (negative = inside), `seconds` after `now`.
    func fix(_ place: Place, edge: Double, accuracy: Double, at seconds: TimeInterval = 0, speed: Double = -1) -> Fix {
        let north = place.radius + edge
        return Fix(latitude: place.latitude + north / 111_320, longitude: place.longitude,
                   accuracy: accuracy, speed: speed, at: now.addingTimeInterval(seconds))
    }

    /// Feeds fixes in order, each read when it was taken.
    func run(_ place: Place, _ fixes: [Fix], from start: PresenceRules.PlaceState = .init()) -> PresenceRules.PlaceState {
        fixes.reduce(start) { PresenceRules.step($0, place: place, reading: .fix($1), now: $1.at) }
    }

    func inside(_ place: Place) -> PresenceRules.PlaceState {
        run(place, [fix(place, edge: -place.radius, accuracy: 10)])
    }

    func geofence(_ state: PresenceRules.PlaceState, _ place: Place, _ presence: Presence, at seconds: TimeInterval) -> PresenceRules.PlaceState {
        let at = now.addingTimeInterval(seconds)
        return PresenceRules.step(state, place: place, reading: .geofence(place.id, presence, at: at), now: at)
    }

    // MARK: Unblocking

    @Test func oneAccurateFixInsideUnblocks() {
        let s = inside(gym)
        #expect(s.presence == .inside)
        #expect(s.reason == .accurateFixInside)
    }

    @Test func twoWifiFixesInsideUnblock() {
        // 10 m inside a 100 m place at ±50 m: leans inside, but one isn't enough.
        let one = run(home, [fix(home, edge: -10, accuracy: 50)])
        #expect(one.presence == .unknown)
        let two = run(home, [fix(home, edge: -10, accuracy: 50), fix(home, edge: -12, accuracy: 50, at: 6)])
        #expect(two.presence == .inside)
        #expect(two.reason == .twoFixesInside)
    }

    @Test func twoFixesTooCloseTogetherDoNotUnblock() {
        let s = run(home, [fix(home, edge: -10, accuracy: 50), fix(home, edge: -10, accuracy: 50, at: 3)])
        #expect(s.presence == .unknown)
    }

    @Test func standingJustOutsideNeverUnblocks() {
        let fixes = (0..<20).map { fix(home, edge: 10, accuracy: 20, at: Double($0) * 6) }
        #expect(run(home, fixes).presence != .inside)
    }

    @Test func aVeryAccurateFixJustOutsideDoesNotUnblock() {
        // Seen in the Simulator (2026-11-23): ±5 m, 19 m past the edge, unblocked through the slack.
        #expect(run(gym, [fix(gym, edge: 19, accuracy: 5)]).presence == .unknown)
        #expect(run(gym, [fix(gym, edge: 1, accuracy: 3)]).presence == .unknown)
        #expect(run(gym, [fix(gym, edge: -1, accuracy: 3)]).presence == .inside)
    }

    @Test func jitterAcrossTheEdgeDoesNotUnblock() {
        let fixes = (0..<20).map { fix(home, edge: $0 % 2 == 0 ? -10 : 10, accuracy: 40, at: Double($0) * 3) }
        #expect(run(home, fixes).presence != .inside)
    }

    @Test func aWideFixAtASmallPlaceDoesNotUnblockAlone() {
        // At the center of a 50 m place, but ±45 m is too wide for a single fix to trust.
        let tiny = Place(name: "Desk", latitude: 47.65, longitude: -122.30, radius: 50)
        #expect(run(tiny, [fix(tiny, edge: -50, accuracy: 45)]).presence == .unknown)
    }

    @Test func staleAndFutureFixesAreIgnored() {
        let center = fix(gym, edge: -150, accuracy: 10)
        let stale = PresenceRules.step(.init(), place: gym, reading: .fix(center), now: now.addingTimeInterval(30))
        #expect(stale.presence == .unknown)
        let future = PresenceRules.step(.init(), place: gym, reading: .fix(center), now: now.addingTimeInterval(-30))
        #expect(future.presence == .unknown)
        let invalid = run(gym, [fix(gym, edge: -150, accuracy: -1)])
        #expect(invalid.presence == .unknown)
    }

    // MARK: Blocking

    @Test func twoGPSFixesOutsideBlock() {
        let s = run(gym, [fix(gym, edge: 80, accuracy: 10, at: 20), fix(gym, edge: 95, accuracy: 10, at: 32)], from: inside(gym))
        #expect(s.presence == .outside)
        #expect(s.reason == .twoFixesOutside)
    }

    @Test func oneGPSFixOutsideDoesNotBlock() {
        let s = run(gym, [fix(gym, edge: 80, accuracy: 10, at: 20)], from: inside(gym))
        #expect(s.presence == .inside)
    }

    @Test func twoFixesOutsideTooCloseTogetherDoNotBlock() {
        let s = run(gym, [fix(gym, edge: 80, accuracy: 10, at: 20), fix(gym, edge: 85, accuracy: 10, at: 25)], from: inside(gym))
        #expect(s.presence == .inside)
    }

    @Test func wifiFixesFarAwayDoNotBlock() {
        // Indoor Wi-Fi fixes 2 km off: too coarse to block, however many arrive.
        let fixes = (1...10).map { fix(gym, edge: 2_000, accuracy: 40, at: Double($0) * 12) }
        #expect(run(gym, fixes, from: inside(gym)).presence == .inside)
    }

    @Test func anImpossibleJumpDoesNotBlock() {
        // GPS-grade but 3 km away 5 s after being inside: 600 m/s, a bad fix.
        let s = run(gym, [fix(gym, edge: 3_000, accuracy: 10, at: 5), fix(gym, edge: 3_000, accuracy: 10, at: 17)], from: inside(gym))
        #expect(s.presence == .inside)
    }

    @Test func nearTheEdgeOutsideDoesNotBlock() {
        // 20 m past the edge at ±10 m isn't clearly out (needs more than accuracy + 25 m).
        let fixes = (1...10).map { fix(gym, edge: 20, accuracy: 10, at: Double($0) * 12) }
        #expect(run(gym, fixes, from: inside(gym)).presence == .inside)
    }

    @Test func anInsideFixBreaksAnOutsidePair() {
        let s = run(gym, [
            fix(gym, edge: 80, accuracy: 10, at: 20),
            fix(gym, edge: -50, accuracy: 20, at: 25),
            fix(gym, edge: 80, accuracy: 10, at: 32),
        ], from: inside(gym))
        #expect(s.presence == .inside)
    }

    @Test func twoGPSFixesSettleUnknownAsOutside() {
        let s = run(gym, [fix(gym, edge: 300, accuracy: 10), fix(gym, edge: 300, accuracy: 10, at: 12)])
        #expect(s.presence == .outside)
    }

    // MARK: iOS's readings

    @Test func iOSInsideIsTheFallback() {
        let s = geofence(.init(), gym, .inside, at: 0)
        #expect(s.presence == .inside)
        #expect(s.reason == .geofenceInside)
    }

    @Test func iOSInsideIsIgnoredWhenARecentFixSaysOutside() {
        let out = run(gym, [fix(gym, edge: 200, accuracy: 50)])
        #expect(geofence(out, gym, .inside, at: 20).presence == .unknown)
    }

    @Test func iOSExitIsIgnoredWhenARecentFixSaysInside() {
        let s = run(gym, [fix(gym, edge: -60, accuracy: 30, at: 30)], from: inside(gym))
        #expect(geofence(s, gym, .outside, at: 60).presence == .inside)
    }

    @Test func iOSExitBlocksWhenNoFixSaysOtherwise() {
        let s = geofence(inside(gym), gym, .outside, at: 120)
        #expect(s.presence == .outside)
        #expect(s.reason == .geofenceOutside)
    }

    /// The reviewer's case for the rejected plan: iOS never thought you were inside. Its old
    /// "outside" reading, read again on later passes, must not undo an unblock from fixes.
    @Test func aStaleIOSReadingNeverUndoesANewerDecision() {
        var s = inside(home)
        s = geofence(s, home, .outside, at: -300) // the record iOS kept from before you arrived
        #expect(s.presence == .inside)
        s = geofence(s, home, .outside, at: -300) // read again on the next pass
        #expect(s.presence == .inside)
        let decision = LockRules.decide(.init(places: [home], session: UnlockSession(placeID: home.id, startedAt: now),
                                              presence: PresenceRules.presence([home.id: s]), hasAlways: true,
                                              now: now.addingTimeInterval(60)))
        #expect(decision == .stayUnlocked)
    }

    @Test func iOSReadingsOnlyTouchTheirOwnPlace() {
        let states = PresenceRules.step([:], places: [gym, home], reading: .geofence(gym.id, .inside, at: now), now: now)
        #expect(states[gym.id]?.presence == .inside)
        #expect(states[home.id]?.presence == .unknown)
    }

    // MARK: With LockRules

    @Test func aWaitingPlaceUnblocksOnlyOnceItsWaitEnds() {
        var waiting = home
        waiting.activeAfter = now.addingTimeInterval(3_600)
        let presence = PresenceRules.presence([waiting.id: inside(waiting)])
        let before = LockRules.decide(.init(places: [waiting], session: nil, presence: presence, hasAlways: true, now: now))
        #expect(before == .stayLocked)
        let after = LockRules.decide(.init(places: [waiting], session: nil, presence: presence, hasAlways: true,
                                           now: now.addingTimeInterval(3_601)))
        #expect(after == .unlock(at: waiting.id))
    }

    @Test func oneFixStepsEveryPlace() {
        let states = PresenceRules.step([:], places: [gym, home], reading: .fix(fix(gym, edge: -150, accuracy: 10)), now: now)
        #expect(states[gym.id]?.presence == .inside)
        #expect(states[home.id]?.presence == .unknown) // ~1.3 km away at ±10 m: one fix, no pair yet
    }
}
