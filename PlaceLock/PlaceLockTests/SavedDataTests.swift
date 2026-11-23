import Foundation
import Testing
@testable import PlaceLock

/// Loading saved places, visits, the session and settings from empty, damaged or older data.
/// Safe means: keep blocking, keep whatever reads, and set the rest aside.
struct SavedDataTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func json(_ text: String) -> Data { Data(text.utf8) }

    let gymID = "0B5D3E1A-1111-4F4F-9C9C-000000000001"
    let homeID = "0B5D3E1A-1111-4F4F-9C9C-000000000002"

    var gym: String { #"{"id":"\#(gymID)","name":"Gym","latitude":47.65,"longitude":-122.30,"radius":150}"# }
    var home: String { #"{"id":"\#(homeID)","name":"Home","latitude":47.66,"longitude":-122.31,"radius":100,"activeAfter":800000000}"# }

    // MARK: Places

    @Test func nothingSavedIsMissingNotAnError() {
        let outcome = SavedData.decodeList(of: Place.self, from: nil)
        #expect(outcome.value == nil)
        #expect(!outcome.lostSomething)
    }

    @Test func savedPlacesLoad() throws {
        let places = [Place(name: "Gym", latitude: 47.65, longitude: -122.30, radius: 150)]
        let outcome = SavedData.decodeList(of: Place.self, from: try JSONEncoder().encode(places))
        #expect(outcome.value == places)
        #expect(!outcome.lostSomething)
    }

    @Test func anEmptyListIsNotAnError() {
        let outcome = SavedData.decodeList(of: Place.self, from: json("[]"))
        #expect(outcome.value == [])
        #expect(!outcome.lostSomething)
    }

    @Test func oneDamagedPlaceKeepsTheOthers() {
        let damaged = #"{"id":"not-a-uuid","name":"Cafe","latitude":"north","radius":100}"#
        let outcome = SavedData.decodeList(of: Place.self, from: json("[\(gym),\(damaged),\(home)]"))
        #expect(outcome.value?.map(\.name) == ["Gym", "Home"])
        #expect(outcome.lostSomething)
        guard case .partial(_, let dropped) = outcome else { Issue.record("expected partial"); return }
        #expect(dropped == 1)
    }

    @Test func placesSavedBeforeDelaysExistedStillLoad() {
        // No `address`, `activeAfter` or `pendingChange`: the place is active.
        let outcome = SavedData.decodeList(of: Place.self, from: json("[\(gym)]"))
        let place = outcome.value?.first
        #expect(place?.id == UUID(uuidString: gymID))
        #expect(place?.isActive(at: now) == true)
        #expect(!outcome.lostSomething)
    }

    @Test func placesThatArentAListAreUnreadable() {
        for stored in [json(gym), json("{not json"), Data(), "places", 42] as [Any] {
            let outcome = SavedData.decodeList(of: Place.self, from: stored)
            #expect(outcome.value == nil)
            #expect(outcome.lostSomething)
        }
    }

    // MARK: Visits and place slots

    @Test func oneDamagedVisitKeepsTheOthers() {
        let good = #"{"placeID":"\#(gymID)","start":799990000,"end":799995000}"#
        let bad = #"{"placeID":"\#(gymID)","start":"yesterday"}"#
        let outcome = SavedData.decodeList(of: Visit.self, from: json("[\(bad),\(good)]"))
        #expect(outcome.value?.count == 1)
        #expect(outcome.value?.first?.placeID == UUID(uuidString: gymID))
        #expect(outcome.lostSomething)
    }

    @Test func oneDamagedSlotKeepsTheOthers() {
        let outcome = SavedData.decodeList(of: String.self, from: json(#"["Home",7,"Gym"]"#))
        #expect(outcome.value == ["Home", "Gym"])
        #expect(outcome.lostSomething)
    }

    // MARK: Session

    @Test func noSessionMeansLocked() {
        #expect(SavedData.decode(UnlockSession.self, from: nil).value == nil)
    }

    @Test func aDamagedSessionMeansLocked() {
        for stored in [json(#"{"placeID":"\#(gymID)"}"#), json("garbage"), "session"] as [Any] {
            let outcome = SavedData.decode(UnlockSession.self, from: stored)
            #expect(outcome.value == nil)
            #expect(outcome.lostSomething)
        }
    }

    @Test func aSessionSavedBeforeVisitIDsExistedStillLoads() {
        let outcome = SavedData.decode(UnlockSession.self, from: json(#"{"placeID":"\#(gymID)","startedAt":799999000}"#))
        let session = outcome.value
        #expect(session?.placeID == UUID(uuidString: gymID))
        #expect(session?.visitStartedAt == Date(timeIntervalSinceReferenceDate: 799_999_000))
    }

    // MARK: Block list

    @Test func aBlockListSavedBeforeRemovalDelaysStillLoads() {
        let outcome = SavedData.decode(BlockList.self, from: json(#"{"simulatedApps":["Instagram","TikTok"]}"#))
        #expect(outcome.value?.simulatedApps == ["Instagram", "TikTok"])
        #expect(outcome.value?.pendingRemovals.isEmpty == true)
    }

    @Test func damagedRemovalDatesKeepTheAppsBlocked() throws {
        // The held app is still in the list, so dropping its date keeps it blocked.
        let stored = json(#"{"simulatedApps":["Instagram","TikTok"],"pendingRemovals":{"simulated":{"TikTok":"soon"}}}"#)
        let list = try #require(SavedData.decode(BlockList.self, from: stored).value)
        #expect(list.simulatedApps == ["Instagram", "TikTok"])
        #expect(list.pendingRemovals.isEmpty)
    }

    @Test func damagedStandInNamesKeepTheRest() throws {
        var saved = BlockList()
        saved.simulatedApps = ["Instagram"]
        saved.pendingRemovals.simulated = ["TikTok": now]
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        object["simulatedApps"] = "Instagram" // a string where a list belongs
        let stored = try JSONSerialization.data(withJSONObject: object)
        let list = try #require(SavedData.decode(BlockList.self, from: stored).value)
        #expect(list.simulatedApps.isEmpty)
        #expect(list.pendingRemovals.simulated["TikTok"] == now)
    }

    @Test func anUnreadableAppSelectionIsReported() {
        let outcome = SavedData.decode(BlockList.self, from: json(#"{"selection":"damaged","simulatedApps":["X"]}"#))
        #expect(outcome.value == nil)
        #expect(outcome.lostSomething)
    }

    // MARK: Setup window

    @Test func firstLaunchGetsTheSetupDay() {
        #expect(SavedData.setupEnd(.missing, now: now) == now.addingTimeInterval(PlaceRules.changeDelay))
    }

    @Test func aSavedSetupEndIsKept() {
        let saved = now.addingTimeInterval(3600)
        #expect(SavedData.setupEnd(SavedData.decode(Date.self, from: try? JSONEncoder().encode(saved)), now: now) == saved)
    }

    @Test func aDamagedSetupEndDoesNotReopenSetup() {
        let outcome = SavedData.decode(Date.self, from: json(#""tomorrow""#))
        #expect(outcome.lostSomething)
        #expect(SavedData.setupEnd(outcome, now: now) == .distantPast)
    }

    // MARK: Setting damaged data aside

    func scratchDefaults() throws -> UserDefaults {
        let name = "SavedDataTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func damagedDataIsCopiedAsideOnce() throws {
        let defaults = try scratchDefaults()
        let first = json("[\(gym),{\"broken\":true}]")
        defaults.set(first, forKey: "places")
        let outcome = Storage.load("places", in: defaults) { SavedData.decodeList(of: Place.self, from: $0) }
        #expect(outcome.value?.map(\.name) == ["Gym"])
        #expect(defaults.data(forKey: "unreadable.places") == first)

        // A later problem doesn't overwrite the first copy.
        defaults.set(json("garbage"), forKey: "places")
        _ = Storage.load("places", in: defaults) { SavedData.decodeList(of: Place.self, from: $0) }
        #expect(defaults.data(forKey: "unreadable.places") == first)
    }

    @Test func readableDataIsNotCopiedAside() throws {
        let defaults = try scratchDefaults()
        defaults.set(json("[\(gym)]"), forKey: "places")
        _ = Storage.load("places", in: defaults) { SavedData.decodeList(of: Place.self, from: $0) }
        _ = Storage.load("session", in: defaults) { SavedData.decode(UnlockSession.self, from: $0) }
        #expect(defaults.object(forKey: "unreadable.places") == nil)
        #expect(defaults.object(forKey: "unreadable.session") == nil)
    }
}
