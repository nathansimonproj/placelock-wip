import CoreLocation
import Foundation
import Testing
@testable import PlaceLock

/// What the Add place search field shows once a direct search (pressing Search before the
/// type-ahead answered) comes back. Each check runs synchronously on the main actor, so the
/// type-ahead's own answer can't land in the middle.
@MainActor
struct PlaceSearchTests {
    private let place = PlaceResult(name: "Smith Hall", address: nil,
                                    coordinate: CLLocationCoordinate2D(latitude: 47.656, longitude: -122.307))

    @Test func noMatchesStopsTheSpinner() {
        let search = PlaceSearch()
        search.query = "xyzzy cafe"
        #expect(search.isSearching)
        #expect(search.finishDirectSearch("xyzzy cafe", found: nil, error: nil) == nil)
        // Not searching any more, so the slow-connection timer won't replace "No matches".
        #expect(!search.isSearching)
        #expect(search.message == PlaceSearch.noMatches)
    }

    @Test func failureStopsTheSpinnerAndSaysWhy() {
        let search = PlaceSearch()
        search.query = "Smith Hall"
        #expect(search.finishDirectSearch("Smith Hall", found: nil, error: URLError(.notConnectedToInternet)) == nil)
        #expect(!search.isSearching)
        #expect(search.message?.hasPrefix("Search isn't available right now") == true)
    }

    @Test func foundStopsTheSpinnerAndReturnsThePlace() {
        let search = PlaceSearch()
        search.query = "Smith Hall"
        #expect(search.finishDirectSearch("Smith Hall", found: place, error: nil)?.name == "Smith Hall")
        #expect(!search.isSearching)
    }

    @Test func answerForOldTextIsDropped() {
        let search = PlaceSearch()
        search.query = "Gates"
        #expect(search.finishDirectSearch("Smith Hall", found: place, error: nil) == nil)
        #expect(search.finishDirectSearch("Smith Hall", found: nil, error: nil) == nil)
        // Still waiting on the type-ahead for "Gates"; nothing about "Smith Hall" is shown.
        #expect(search.isSearching)
        #expect(search.message == nil)
    }
}
