import Foundation
import Testing
@testable import PlaceLock

/// The lock/unlock decision: blocked by default, unblocked inside an active place.
struct LockRulesTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let gym = Place(name: "Gym", latitude: 47.6537, longitude: -122.3012, radius: 150)
    let home = Place(name: "Home", latitude: 47.6634, longitude: -122.3139, radius: 150)

    func decide(session: UnlockSession? = nil, paused: Set<UUID> = [], presence: [UUID: Presence] = [:],
                hasAlways: Bool = true, places: [Place]? = nil, checkCap: Bool = true,
                at time: Date? = nil) -> (LockRules.Action, Set<UUID>) {
        let result = LockRules.decide(.init(places: places ?? [gym, home], session: session, paused: paused,
                                            presence: presence, hasAlways: hasAlways, now: time ?? now,
                                            checkSessionCap: checkCap))
        return (result.action, result.paused)
    }

    func session(at place: Place, startedAt: Date? = nil) -> UnlockSession {
        UnlockSession(placeID: place.id, startedAt: startedAt ?? now)
    }

    // MARK: Locked

    @Test func staysLockedAwayFromEveryPlace() {
        #expect(decide(presence: [gym.id: .outside, home.id: .outside]).0 == .stayLocked)
    }

    @Test func unknownReadingsDoNotUnlock() {
        #expect(decide(presence: [gym.id: .unknown]).0 == .stayLocked)
    }

    @Test func unlocksOnArrival() {
        #expect(decide(presence: [gym.id: .inside, home.id: .outside]).0 == .unlock(at: gym.id))
    }

    @Test func doesNotUnlockAtAPlaceStillInItsDelay() {
        var waiting = gym
        waiting.activeAfter = now.addingTimeInterval(60)
        #expect(decide(presence: [gym.id: .inside], places: [waiting]).0 == .stayLocked)
    }

    @Test func unlocksOnceTheDelayHasPassed() {
        var ready = gym
        ready.activeAfter = now.addingTimeInterval(-1)
        #expect(decide(presence: [gym.id: .inside], places: [ready]).0 == .unlock(at: gym.id))
    }

    @Test func withoutAlwaysLocationNothingUnlocks() {
        #expect(decide(presence: [gym.id: .inside], hasAlways: false).0 == .stayLocked)
    }

    // MARK: Lock until I leave

    @Test func pausedPlaceStaysLockedWhileYouAreThere() {
        let (action, paused) = decide(paused: [gym.id], presence: [gym.id: .inside])
        #expect(action == .stayLocked)
        #expect(paused == [gym.id])
    }

    @Test func leavingAPausedPlaceClearsThePause() {
        let (action, paused) = decide(paused: [gym.id], presence: [gym.id: .outside])
        #expect(action == .stayLocked)
        #expect(paused.isEmpty)
    }

    @Test func pauseOnlyAppliesToThatPlace() {
        let (action, _) = decide(paused: [gym.id], presence: [gym.id: .inside, home.id: .inside])
        #expect(action == .unlock(at: home.id))
    }

    // MARK: Unlocked

    @Test func staysUnlockedWhileInside() {
        #expect(decide(session: session(at: gym), presence: [gym.id: .inside]).0 == .stayUnlocked)
    }

    @Test func unknownReadingDoesNotEndASession() {
        #expect(decide(session: session(at: gym), presence: [gym.id: .unknown]).0 == .stayUnlocked)
    }

    @Test func leavingLocks() {
        let action = decide(session: session(at: gym), presence: [gym.id: .outside]).0
        #expect(action == .lock(reason: "Left Gym, apps locked."))
    }

    @Test func leavingIntoAnotherPlaceMovesTheSession() {
        let action = decide(session: session(at: gym), presence: [gym.id: .outside, home.id: .inside]).0
        #expect(action == .move(from: gym.id, to: home.id))
    }

    @Test func leavingIntoAPausedPlaceLocks() {
        let action = decide(session: session(at: gym), paused: [home.id],
                            presence: [gym.id: .outside, home.id: .inside]).0
        #expect(action == .lock(reason: "Left Gym, apps locked."))
    }

    @Test func deletedPlaceLocks() {
        let action = decide(session: session(at: gym), presence: [:], places: [home]).0
        #expect(action == .lock(reason: "That place was deleted. Apps locked."))
    }

    @Test func losingAlwaysLocationLocks() {
        let action = decide(session: session(at: gym), presence: [gym.id: .inside], hasAlways: false).0
        #expect(action == .lock(reason: "Location is no longer set to Always. Apps locked."))
    }

    // MARK: 8 h cap

    @Test func longSessionsGetRechecked() {
        let start = now.addingTimeInterval(-LockRules.maxSession - 1)
        #expect(decide(session: session(at: gym, startedAt: start), presence: [gym.id: .inside]).0 == .recheck(gym.id))
    }

    @Test func noRecheckBeforeTheCap() {
        let start = now.addingTimeInterval(-LockRules.maxSession + 60)
        #expect(decide(session: session(at: gym, startedAt: start), presence: [gym.id: .inside]).0 == .stayUnlocked)
    }

    @Test func noRecheckWhileSimulating() {
        let start = now.addingTimeInterval(-LockRules.maxSession - 1)
        let action = decide(session: session(at: gym, startedAt: start), presence: [gym.id: .inside], checkCap: false).0
        #expect(action == .stayUnlocked)
    }
}
