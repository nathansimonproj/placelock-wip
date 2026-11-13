import MapKit

/// One row in the type-ahead list.
struct PlaceSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    fileprivate let completion: MKLocalSearchCompletion
}

/// A suggestion resolved to a real spot on the map.
struct PlaceResult {
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D
}

/// Type-ahead place search, currently backed by Apple Maps (free, no API key).
///
/// Swap point for Google Places: keep this class's public surface (`query`, `suggestions`,
/// `message`, `bias(around:)`, `resolve(_:)`) and replace the MapKit internals.
@MainActor
final class PlaceSearch: NSObject, ObservableObject {
    @Published var query = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard trimmed != oldValue.trimmingCharacters(in: .whitespaces) else { return }
            slowTimer?.cancel()
            if trimmed.isEmpty {
                suggestions = []; message = nil; isSearching = false
            } else {
                // Keep the previous suggestions on screen while the new ones load.
                isSearching = true
                slowTimer = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.slowAfter))
                    guard let self, !Task.isCancelled, self.isSearching else { return }
                    // Stop the spinner so the screen doesn't look stuck. Late results still show.
                    self.isSearching = false
                    self.message = "Search is taking a while, so your connection may be slow. You can clear the search and drag the map to drop a pin instead."
                    Log.app.info("Search slow: no response after \(Int(Self.slowAfter))s for \(trimmed, privacy: .public)")
                }
            }
            completer.queryFragment = trimmed
        }
    }
    @Published private(set) var suggestions: [PlaceSuggestion] = []
    /// Waiting on Apple for the current query.
    @Published private(set) var isSearching = false
    /// "No matches", "slow connection" or a network error, shown under the search field.
    @Published private(set) var message: String?

    private static let slowAfter: Double = 8
    private let completer = MKLocalSearchCompleter()
    private var slowTimer: Task<Void, Never>?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    /// Prefer results near `center` (the user's location) — otherwise "Gates Center" finds New York.
    func bias(around center: CLLocationCoordinate2D) {
        completer.region = MKCoordinateRegion(center: center, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
    }

    func resolve(_ suggestion: PlaceSuggestion) async throws -> PlaceResult {
        let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: suggestion.completion)).start()
        guard let item = response.mapItems.first else { throw URLError(.cannotFindHost) }
        let name = item.name ?? suggestion.title
        if #available(iOS 26, *) {
            return PlaceResult(name: name, address: item.address?.shortAddress ?? suggestion.subtitle,
                               coordinate: item.location.coordinate)
        } else {
            return PlaceResult(name: name, address: item.placemark.title ?? suggestion.subtitle,
                               coordinate: item.placemark.coordinate)
        }
    }
}

extension PlaceSearch: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let rows = completer.results.map {
            PlaceSuggestion(title: $0.title, subtitle: $0.subtitle, completion: $0)
        }
        Task { @MainActor in
            guard !self.query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            Log.app.info("Search results: \(rows.count) for \(self.query, privacy: .public)")
            self.slowTimer?.cancel()
            self.isSearching = false
            self.suggestions = rows
            self.message = rows.isEmpty ? "No matches. Try the full name, or move the map to drop a pin." : nil
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        let text = (error as? MKError)?.code == .placemarkNotFound
            ? "No matches. Try the full name, or move the map to drop a pin."
            : "Search isn't available right now (\(error.localizedDescription)). You can still move the map to drop a pin."
        Task { @MainActor in
            Log.app.error("Search failed: \(error.localizedDescription, privacy: .public)")
            self.slowTimer?.cancel()
            self.isSearching = false
            self.suggestions = []
            self.message = text
        }
    }
}
