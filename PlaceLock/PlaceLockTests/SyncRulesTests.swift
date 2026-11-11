import Foundation
import Testing
@testable import PlaceLock

/// Sync decisions: what gets queued, how pulled rows merge, and the outbox's rules.
struct SyncRulesTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let gym = Place(name: "Gym", latitude: 47.6537, longitude: -122.3012, radius: 150)
    let home = Place(name: "Home", latitude: 47.6634, longitude: -122.3139, radius: 150)

    func later(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }

    func merge(local: [Place], editedAt: [UUID: Date] = [:], remote: [PlaceRecord],
               firstSync: Bool = false) -> SyncRules.MergeResult {
        SyncRules.merge(.init(local: local, editedAt: editedAt, remote: remote, isFirstSync: firstSync, now: now))
    }

    // MARK: Local edits → uploads

    @Test func addedEditedAndDeletedPlacesAreQueued() {
        var renamed = gym
        renamed.name = "IMA"
        let library = Place(name: "Library", latitude: 47.656, longitude: -122.31, radius: 120)
        let records = SyncRules.placeChanges(old: [gym, home], new: [renamed, library], now: now)

        #expect(records.count == 3)
        #expect(records.contains { $0.id == gym.id && $0.name == "IMA" && $0.deletedAt == nil })
        #expect(records.contains { $0.id == library.id && $0.deletedAt == nil })
        #expect(records.contains { $0.id == home.id && $0.deletedAt == now })
        #expect(records.allSatisfy { $0.updatedAt == now })
    }

    @Test func unchangedPlacesAreNotQueued() {
        #expect(SyncRules.placeChanges(old: [gym, home], new: [gym, home], now: now).isEmpty)
    }

    @Test func recordFitsServerLimits() {
        let long = Place(name: String(repeating: "x", count: 90), address: String(repeating: "a", count: 300),
                         latitude: 0, longitude: 0, radius: 40)
        let record = PlaceRecord(long, updatedAt: now)
        #expect(record.name.count == PlaceRecord.maxName)
        #expect(record.address?.count == PlaceRecord.maxAddress)
        #expect(record.radiusM == 100)
    }

    @Test func recordRoundTripsPendingChange() {
        var place = gym
        place.activeAfter = later(3600)
        place.pendingChange = .init(latitude: 47.66, longitude: -122.30, radius: 300, appliesAt: later(7200))
        #expect(PlaceRecord(place, updatedAt: now).place == place)
    }

    @Test func nullFieldsAreSentSoTheServerClearsThem() throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PlaceRecord(gym, updatedAt: now)))
            as? [String: Any]
        #expect(json?["pending_applies_at"] is NSNull)
        #expect(json?["deleted_at"] is NSNull)
        #expect(json?["synced_at"] == nil) // server-owned, never uploaded
    }

    // MARK: Merging pulled rows

    @Test func newerRemoteEditWins() {
        var remote = PlaceRecord(gym, updatedAt: later(60))
        remote.name = "IMA"
        let result = merge(local: [gym], editedAt: [gym.id: now], remote: [remote])
        #expect(result.places?.first?.name == "IMA")
        #expect(result.editedAt[gym.id] == later(60))
    }

    @Test func newerLocalEditWins() {
        var remote = PlaceRecord(gym, updatedAt: now)
        remote.name = "Old name"
        let result = merge(local: [gym], editedAt: [gym.id: later(60)], remote: [remote])
        #expect(result.places == nil)
    }

    @Test func ownEchoChangesNothing() {
        let result = merge(local: [gym], editedAt: [gym.id: now], remote: [PlaceRecord(gym, updatedAt: now)])
        #expect(result.places == nil)
    }

    @Test func remoteTombstoneDeletesLocalPlace() {
        let tombstone = PlaceRecord(gym, updatedAt: later(60), deletedAt: later(60))
        let result = merge(local: [gym, home], editedAt: [gym.id: now], remote: [tombstone])
        #expect(result.places == [home])
    }

    @Test func remotePlaceFromAnotherDeviceIsAdded() {
        let result = merge(local: [gym], remote: [PlaceRecord(home, updatedAt: now)])
        #expect(result.places == [gym, home])
    }

    // MARK: First sync

    @Test func firstSyncUploadsExistingPlaces() {
        let result = merge(local: [gym, home], remote: [], firstSync: true)
        #expect(result.places == nil)
        #expect(Set(result.uploads.map(\.id)) == [gym.id, home.id])
        #expect(result.uploads.allSatisfy { $0.updatedAt == now })
    }

    @Test func reinstallRestoresAndDropsReseededStarterPlace() {
        // The server has this account's Gym (edited). A reinstall seeded a fresh Gym with a new id.
        var savedGym = Place(name: "Gym", latitude: 47.65, longitude: -122.30, radius: 250)
        savedGym.address = "My gym"
        let reseeded = gym
        let result = merge(local: [reseeded, home], remote: [PlaceRecord(savedGym, updatedAt: now)], firstSync: true)

        #expect(result.places?.map(\.id).sorted() == [savedGym.id, home.id].sorted())
        #expect(result.places?.first { $0.id == savedGym.id }?.radius == 250)
        #expect(result.uploads.map(\.id) == [home.id]) // only the place the server doesn't have
    }

    @Test func editedPlaceWithSameNameIsKeptOnFirstSync() {
        // Edited on this phone before sync ran, so it isn't a re-seeded duplicate.
        let mine = Place(name: "Gym", latitude: 1, longitude: 1, radius: 150)
        let result = merge(local: [mine], editedAt: [mine.id: now],
                           remote: [PlaceRecord(gym, updatedAt: now)], firstSync: true)
        #expect(result.places?.count == 2)
        #expect(result.uploads.map(\.id) == [mine.id])
    }

    // MARK: Setup window

    @Test func earlierSetupEndWins() {
        #expect(SyncRules.mergedSetupEnd(local: later(86_400), remote: now) == now)
        #expect(SyncRules.mergedSetupEnd(local: now, remote: later(86_400)) == now)
        #expect(SyncRules.mergedSetupEnd(local: now, remote: nil) == now)
    }

    // MARK: Outbox

    @Test func outboxKeepsNewestVersionOfARow() {
        var outbox = Outbox()
        outbox.add(.place(PlaceRecord(gym, updatedAt: later(60))))
        outbox.add(.place(PlaceRecord(gym, updatedAt: now))) // older, arrives late
        #expect(outbox.count == 1)
        #expect(outbox.places.first?.updatedAt == later(60))
    }

    @Test func outboxSendsPlacesBeforeSessions() {
        var outbox = Outbox()
        let session = UnlockSession(placeID: home.id, startedAt: now)
        outbox.add(.session(SessionRecord(session, updatedAt: now)))
        outbox.add(.place(PlaceRecord(home, updatedAt: now)))
        #expect(outbox.places.map(\.id) == [home.id])
        #expect(outbox.sessions.map(\.id) == [session.id])
    }

    @Test func editDuringUploadStaysQueued() {
        var outbox = Outbox()
        let sent = SyncChange.place(PlaceRecord(gym, updatedAt: now))
        outbox.add(sent)
        var renamed = gym
        renamed.name = "IMA"
        outbox.add(.place(PlaceRecord(renamed, updatedAt: later(1)))) // edited while in flight
        outbox.remove([sent])
        #expect(outbox.places.map(\.name) == ["IMA"])
    }

    @Test func sessionEndIsNeverBeforeItsStart() {
        let session = UnlockSession(placeID: gym.id, startedAt: now)
        let record = SessionRecord(session, endedAt: now.addingTimeInterval(-5), reason: .left, updatedAt: now)
        #expect(record.endedAt == now)
    }

    @Test func permanentFailuresAreClassified() {
        #expect(SyncRules.isPermanentFailure(postgresCode: "23514")) // check constraint
        #expect(SyncRules.isPermanentFailure(postgresCode: "42501")) // row-level security
        #expect(!SyncRules.isPermanentFailure(postgresCode: "PGRST301")) // JWT expired: retry
        #expect(!SyncRules.isPermanentFailure(postgresCode: nil))
    }

    @Test func retryBacksOffToFiveMinutes() {
        #expect(SyncRules.retryDelay(afterFailures: 1) == 5)
        #expect(SyncRules.retryDelay(afterFailures: 3) == 20)
        #expect(SyncRules.retryDelay(afterFailures: 20) == 300)
    }

    // MARK: Saved sessions

    @Test func sessionSavedBeforeSyncStillLoads() throws {
        let old = #"{"placeID":"\#(gym.id.uuidString)","startedAt":\#(now.timeIntervalSinceReferenceDate)}"#
        let session = try JSONDecoder().decode(UnlockSession.self, from: Data(old.utf8))
        #expect(session.placeID == gym.id)
        #expect(session.visitStartedAt == now)
    }

    @Test func recheckKeepsTheSameVisit() {
        let session = UnlockSession(placeID: gym.id, startedAt: now)
        let rechecked = session.rechecked(at: later(8 * 3600))
        #expect(rechecked.id == session.id)
        #expect(rechecked.visitStartedAt == now)
        #expect(rechecked.startedAt == later(8 * 3600))
    }
}
