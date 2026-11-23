import Foundation
import Testing
@testable import PlaceLock

/// Which circles iOS watches. Identifiers carry the geometry, so syncing is a set difference.
struct GeofenceKeysTests {
    let gym = Place(name: "Gym", latitude: 47.6537, longitude: -122.3012, radius: 150)
    let home = Place(name: "Home", latitude: 47.6634, longitude: -122.3139, radius: 150)
    let max = GeofenceMonitor.maxPlaces

    func key(_ place: Place) -> String { GeofenceKeys.key(for: place) }

    @Test func keyChangesWhenCenterOrRadiusChanges() {
        var moved = gym
        moved.latitude += 0.0001
        var bigger = gym
        bigger.radius = 175
        #expect(key(moved) != key(gym))
        #expect(key(bigger) != key(gym))
        #expect(key(gym).hasPrefix(gym.id.uuidString + "@"))
    }

    @Test func keyIgnoresNameActiveAfterAndPendingChange() {
        var edited = gym
        edited.name = "IMA"
        edited.address = "1 Main St"
        edited.activeAfter = .now
        edited.pendingChange = .init(latitude: 1, longitude: 2, radius: 300, appliesAt: .now)
        #expect(key(edited) == key(gym))
    }

    @Test func keyIsTheSameEveryTime() {
        // Not built from hashValue, which changes every launch.
        let copy = Place(id: gym.id, name: "Gym", latitude: 47.6537, longitude: -122.3012, radius: 150)
        #expect(key(copy) == key(gym))
        #expect(key(gym) == "\(gym.id.uuidString)@47.653700,-122.301200,150")
    }

    @Test func diffKeepsUnchangedPlaces() {
        let plan = GeofenceKeys.diff(current: [key(gym), key(home)], places: [gym, home], max: max)
        #expect(plan.isEmpty)
    }

    @Test func diffReAddsAMovedPlace() {
        var moved = gym
        moved.longitude += 0.001
        let plan = GeofenceKeys.diff(current: [key(gym), key(home)], places: [moved, home], max: max)
        #expect(plan.remove == [key(gym)])
        #expect(plan.add == [moved])
    }

    @Test func diffRemovesDeletedPlacesAndOldPlainUUIDs() {
        // Builds before 2026-11-22 watched each place under its plain UUID.
        let plan = GeofenceKeys.diff(current: [gym.id.uuidString, key(home)], places: [gym], max: max)
        #expect(Set(plan.remove) == [gym.id.uuidString, key(home)])
        #expect(plan.add == [gym])
    }

    @Test func diffCapsAtMax() {
        let places = (0..<25).map { Place(name: "P\($0)", latitude: 47 + Double($0) / 100, longitude: -122, radius: 100) }
        let plan = GeofenceKeys.diff(current: [], places: places, max: max)
        #expect(plan.add == Array(places.prefix(20)))
    }

    @Test func diffDedupesDuplicateIDs() {
        var twin = gym
        twin.latitude += 0.01 // same id, other circle: the first copy wins
        let plan = GeofenceKeys.diff(current: [], places: [gym, twin, home], max: max)
        #expect(plan.add == [gym, home])
    }

    @Test func diffIsIdempotent() {
        var moved = gym
        moved.radius = 100
        let current = [key(gym), "old-\(UUID().uuidString)"]
        let places = [moved, home]
        let plan = GeofenceKeys.diff(current: current, places: places, max: max)
        let after = current.filter { !plan.remove.contains($0) } + plan.add.map(key)
        #expect(GeofenceKeys.diff(current: after, places: places, max: max).isEmpty)
    }
}
