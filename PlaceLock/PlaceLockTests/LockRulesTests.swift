import Foundation
import Testing
@testable import PlaceLock

/// The lock/unlock decision: blocked by default, unblocked inside an active place.
struct LockRulesTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let gym = Place(name: "Gym", latitude: 47.6537, longitude: -122.3012, radius: 150)
    let home = Place(name: "Home", latitude: 47.6634, longitude: -122.3139, radius: 150)

    func decide(session: UnlockSession? = nil, presence: [UUID: Presence] = [:],
                hasAlways: Bool = true, places: [Place]? = nil, at time: Date? = nil) -> LockRules.Action {
        LockRules.decide(.init(places: places ?? [gym, home], session: session,
                               presence: presence, hasAlways: hasAlways, now: time ?? now))
    }

    func session(at place: Place, startedAt: Date? = nil) -> UnlockSession {
        UnlockSession(placeID: place.id, startedAt: startedAt ?? now)
    }

    // MARK: Locked

    @Test func staysLockedAwayFromEveryPlace() {
        #expect(decide(presence: [gym.id: .outside, home.id: .outside]) == .stayLocked)
    }

    @Test func unknownReadingsDoNotUnlock() {
        #expect(decide(presence: [gym.id: .unknown]) == .stayLocked)
    }

    @Test func unlocksOnArrival() {
        #expect(decide(presence: [gym.id: .inside, home.id: .outside]) == .unlock(at: gym.id))
    }

    @Test func doesNotUnlockAtAPlaceStillInItsDelay() {
        var waiting = gym
        waiting.activeAfter = now.addingTimeInterval(60)
        #expect(decide(presence: [gym.id: .inside], places: [waiting]) == .stayLocked)
    }

    @Test func unlocksOnceTheDelayHasPassed() {
        var ready = gym
        ready.activeAfter = now.addingTimeInterval(-1)
        #expect(decide(presence: [gym.id: .inside], places: [ready]) == .unlock(at: gym.id))
    }

    @Test func withoutAlwaysLocationNothingUnlocks() {
        #expect(decide(presence: [gym.id: .inside], hasAlways: false) == .stayLocked)
    }

    // MARK: Unlocked

    @Test func staysUnlockedWhileInside() {
        #expect(decide(session: session(at: gym), presence: [gym.id: .inside]) == .stayUnlocked)
    }

    @Test func unknownReadingDoesNotEndASession() {
        #expect(decide(session: session(at: gym), presence: [gym.id: .unknown]) == .stayUnlocked)
    }

    @Test func leavingLocks() {
        let action = decide(session: session(at: gym), presence: [gym.id: .outside])
        #expect(action == .lock(reason: "Left Gym, apps blocked."))
    }

    @Test func leavingIntoAnotherPlaceMovesTheSession() {
        let action = decide(session: session(at: gym), presence: [gym.id: .outside, home.id: .inside])
        #expect(action == .move(from: gym.id, to: home.id))
    }

    @Test func unknownSessionPlaceWithAnotherInsideStaysUnlocked() {
        // Only a definite "outside" at the session's place moves or ends it.
        let action = decide(session: session(at: gym), presence: [gym.id: .unknown, home.id: .inside])
        #expect(action == .stayUnlocked)
    }

    @Test func moveSkipsAPlaceStillInItsDelay() {
        var waiting = home
        waiting.activeAfter = now.addingTimeInterval(60)
        let action = decide(session: session(at: gym), presence: [gym.id: .outside, home.id: .inside],
                            places: [gym, waiting])
        #expect(action == .lock(reason: "Left Gym, apps blocked."))
    }

    @Test func firstActiveInsidePlaceWinsWhenSeveralAreInside() {
        let both: [UUID: Presence] = [gym.id: .inside, home.id: .inside]
        #expect(decide(presence: both, places: [gym, home]) == .unlock(at: gym.id))
        #expect(decide(presence: both, places: [home, gym]) == .unlock(at: home.id))
    }

    @Test func deletedPlaceLocks() {
        let action = decide(session: session(at: gym), presence: [:], places: [home])
        #expect(action == .lock(reason: "That place was deleted. Apps blocked."))
    }

    @Test func losingAlwaysLocationLocks() {
        let action = decide(session: session(at: gym), presence: [gym.id: .inside], hasAlways: false)
        #expect(action == .lock(reason: "Location is no longer set to Always. Apps blocked."))
    }

    /// No time limit: a long stay stays unlocked until iOS reports you've left.
    @Test func longStaysStayUnlocked() {
        let start = now.addingTimeInterval(-20 * 3600)
        #expect(decide(session: session(at: gym, startedAt: start), presence: [gym.id: .inside]) == .stayUnlocked)
    }
}
