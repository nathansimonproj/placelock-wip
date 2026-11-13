import Foundation
import Supabase
import Testing
@testable import PlaceLock

/// `SyncEngine`'s passes against a fake server: sign-in, pull, upload, retries, account deletion.
/// The decisions themselves (merging, the outbox) are covered in `SyncRulesTests`.
@MainActor
struct SyncEngineTests {
    let server = FakeServer()
    let phone = FakePhone()
    let defaults: UserDefaults

    let gym = Place(name: "Gym", latitude: 47.6537, longitude: -122.3012, radius: 150)
    let home = Place(name: "Home", latitude: 47.6634, longitude: -122.3139, radius: 150)

    init() {
        let suite = "SyncEngineTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    func makeEngine() -> SyncEngine {
        let phone = self.phone
        return SyncEngine(backend: server, local: { phone }, defaults: defaults)
    }

    func sync(_ engine: SyncEngine) async {
        engine.requestSync()
        await engine.waitUntilIdle()
    }

    // MARK: First sync

    @Test func firstSyncSignsInAndUploadsThisPhonesPlaces() async {
        phone.places = [gym, home]
        let engine = makeEngine()
        await sync(engine)

        #expect(server.signIns == 1)
        #expect(server.pulls == [nil])
        #expect(Set(server.rows.keys) == [gym.id, home.id])
        #expect(engine.pendingCount == 0)
        if case .synced = engine.status {} else { Issue.record("status \(engine.status)") }
    }

    @Test func firstSyncRestoresPlacesFromTheServer() async {
        server.store(PlaceRecord(home, updatedAt: .now))
        let engine = makeEngine()
        await sync(engine)

        #expect(phone.places.map(\.id) == [home.id])
        #expect(server.placeUploads.isEmpty)
    }

    @Test func laterPassesOnlyPullNewRows() async {
        phone.places = [gym]
        let engine = makeEngine()
        await sync(engine) // empty server: records that the first sync happened
        await sync(engine) // pulls back its own upload once (merge ignores it)
        let newest = server.rows[gym.id]?.syncedAt
        await sync(engine)

        #expect(server.signIns == 1) // the saved session is reused
        #expect(server.pulls == [nil, .distantPast, newest])
        #expect(phone.places.map(\.id) == [gym.id])
    }

    // MARK: Uploads

    @Test func localEditsUploadPlacesBeforeSessions() async {
        let engine = makeEngine()
        await sync(engine)
        server.calls = []

        engine.sessionStarted(UnlockSession(placeID: gym.id, startedAt: .now))
        engine.placesChanged(old: [], new: [gym])
        await engine.waitUntilIdle()

        #expect(server.calls.filter { $0.hasPrefix("upsert") } == ["upsert places", "upsert sessions"])
        #expect(engine.pendingCount == 0)
    }

    @Test func offlineKeepsChangesQueuedUntilTheNextPass() async {
        let engine = makeEngine()
        await sync(engine)

        server.failNextCall = URLError(.notConnectedToInternet)
        engine.placesChanged(old: [], new: [gym])
        await engine.waitUntilIdle()
        #expect(engine.status == .failed("Offline"))
        #expect(engine.pendingCount == 1)

        await sync(engine)
        #expect(engine.pendingCount == 0)
        #expect(server.rows[gym.id] != nil)
    }

    @Test func aRowTheServerRejectsIsDroppedAndTheRestUpload() async {
        let engine = makeEngine()
        await sync(engine)

        server.rejected = [home.id]
        engine.placesChanged(old: [], new: [gym, home])
        await engine.waitUntilIdle()

        #expect(server.rows[gym.id] != nil)
        #expect(server.rows[home.id] == nil)
        #expect(engine.pendingCount == 0) // the bad row doesn't block the queue
    }

    @Test func queuedChangesSurviveARelaunch() async {
        let engine = makeEngine()
        await sync(engine)
        server.failNextCall = URLError(.notConnectedToInternet)
        engine.placesChanged(old: [], new: [gym])
        await engine.waitUntilIdle()

        let relaunched = makeEngine()
        #expect(relaunched.pendingCount == 1)
        await sync(relaunched)
        #expect(server.rows[gym.id] != nil)
    }

    // MARK: Account

    @Test func anUnusableSessionStartsANewAccountAndUploadsEverythingAgain() async {
        phone.places = [gym]
        let engine = makeEngine()
        await sync(engine)

        server.wipe() // as if the account were gone
        server.sessionRevoked = true
        await sync(engine)

        #expect(server.signIns == 2)
        #expect(server.pulls.last == .some(nil)) // a full pull for the new account
        #expect(server.rows[gym.id] != nil)
    }

    @Test func offlineDoesNotStartANewAccount() async {
        let engine = makeEngine()
        await sync(engine)

        server.failNextCall = URLError(.notConnectedToInternet)
        await sync(engine)

        #expect(server.signIns == 1)
    }

    @Test func theEarliestSetupWindowEndWins() async {
        let soon = Date.now.addingTimeInterval(3600)
        phone.setupEndsAt = soon.addingTimeInterval(3600)
        server.profile = ProfileRecord(setupEndsAt: soon, updatedAt: .distantPast)
        await sync(makeEngine())
        #expect(phone.setupEndsAt == soon) // the server's earlier end is adopted

        phone.setupEndsAt = soon.addingTimeInterval(-60)
        await sync(makeEngine())
        #expect(server.profile.setupEndsAt == phone.setupEndsAt) // and ours goes up when earlier
    }

    @Test func deletingTheAccountClearsTheServerAndTurnsBackupOff() async throws {
        phone.places = [gym]
        let engine = makeEngine()
        await sync(engine)

        try await engine.deleteAccount()

        #expect(server.accountDeleted)
        #expect(!server.hasStoredSession)
        #expect(server.rows.isEmpty)
        #expect(engine.status == .turnedOff)
        #expect(!engine.isEnabled)
        #expect(phone.places.map(\.id) == [gym.id]) // the phone keeps its places

        // Nothing queues or syncs while backup is off, including after a relaunch.
        server.calls = []
        engine.placesChanged(old: [gym], new: [gym, home])
        await sync(engine)
        #expect(engine.pendingCount == 0)
        #expect(server.calls.isEmpty)
        #expect(makeEngine().status == .turnedOff)
    }

    @Test func turningBackupBackOnStartsANewAccountWithThisPhonesPlaces() async throws {
        phone.places = [gym]
        let engine = makeEngine()
        await sync(engine)
        try await engine.deleteAccount()

        engine.turnBackOn()
        await engine.waitUntilIdle()

        #expect(engine.isEnabled)
        #expect(server.signIns == 2)
        #expect(server.rows[gym.id] != nil)
    }

    @Test func deletingWithNoAccountSkipsTheServer() async throws {
        let engine = makeEngine()
        try await engine.deleteAccount()

        #expect(!server.accountDeleted)
        #expect(engine.status == .turnedOff)
    }

    @Test func aFailedDeleteChangesNothing() async {
        phone.places = [gym]
        let engine = makeEngine()
        await sync(engine)

        server.failNextCall = URLError(.notConnectedToInternet)
        await #expect(throws: URLError.self) { try await engine.deleteAccount() }

        #expect(!server.accountDeleted)
        #expect(server.hasStoredSession)
        #expect(engine.isEnabled)
        #expect(server.rows[gym.id] != nil)
    }
}

// MARK: - Fakes

/// An in-memory server that behaves like the Supabase project for what sync uses.
@MainActor
final class FakeServer: SyncBackend {
    private(set) var hasStoredSession = false
    private(set) var signIns = 0
    private(set) var accountDeleted = false
    /// `syncedAfter` of every pull, in order.
    private(set) var pulls: [Date?] = []
    private(set) var placeUploads: [[PlaceRecord]] = []
    /// Places by id, with the server's `syncedAt` set.
    private(set) var rows: [UUID: PlaceRecord] = [:]
    var profile = ProfileRecord(setupEndsAt: nil, updatedAt: .distantPast)
    /// Every call, e.g. "upsert places".
    var calls: [String] = []

    /// Thrown by the next call, then cleared.
    var failNextCall: Error?
    /// The stored session can't be refreshed any more.
    var sessionRevoked = false
    /// Place ids the server rejects with a check-constraint error.
    var rejected: Set<UUID> = []

    private var clock = Date.now

    func store(_ record: PlaceRecord) {
        clock += 1
        var record = record
        record.syncedAt = clock
        rows[record.id] = record
    }

    func wipe() {
        rows = [:]
        profile = ProfileRecord(setupEndsAt: nil, updatedAt: .distantPast)
    }

    private func call(_ name: String) throws {
        calls.append(name)
        if let error = failNextCall {
            failNextCall = nil
            throw error
        }
    }

    func storedUserID() async throws -> UUID {
        try call("session")
        if sessionRevoked { throw FakeError.sessionRevoked }
        return UUID()
    }

    func signInAnonymously() async throws -> UUID {
        try call("sign in")
        signIns += 1
        hasStoredSession = true
        sessionRevoked = false
        return UUID()
    }

    func places(syncedAfter after: Date?) async throws -> [PlaceRecord] {
        try call("pull")
        pulls.append(after)
        return rows.values
            .filter { row in after.map { row.syncedAt! > $0 } ?? true }
            .sorted { $0.syncedAt! < $1.syncedAt! }
    }

    func profile(of user: UUID) async throws -> ProfileRecord {
        try call("profile")
        return profile
    }

    func updateProfile(_ profile: ProfileRecord, of user: UUID) async throws {
        try call("update profile")
        self.profile = profile
    }

    func upsert(places: [PlaceRecord]) async throws {
        try call("upsert places")
        if places.contains(where: { rejected.contains($0.id) }) {
            throw PostgrestError(code: "23514", message: "new row violates check constraint")
        }
        placeUploads.append(places)
        places.forEach(store)
    }

    func upsert(sessions: [SessionRecord]) async throws {
        try call("upsert sessions")
    }

    func deleteAccount() async throws {
        try call("delete account")
        accountDeleted = true
        wipe()
    }

    func signOut() async {
        calls.append("sign out")
        hasStoredSession = false
    }

    enum FakeError: Error { case sessionRevoked }
}

@MainActor
final class FakePhone: SyncLocal {
    var places: [Place] = []
    var setupEndsAt = Date.distantPast

    func applyRemotePlaces(_ places: [Place]) { self.places = places }
    func adoptSetupEnd(_ date: Date) { setupEndsAt = min(setupEndsAt, date) }
}
