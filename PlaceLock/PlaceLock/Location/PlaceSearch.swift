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
/// `suggestionsQuery`, `message`, `bias(around:)`, `resolve(_:)`, `searchDirectly(_:)`) and
/// replace the MapKit internals.
@MainActor
final class PlaceSearch: NSObject, ObservableObject {
    @Published var query = "" {
        didSet {
            let trimmed = PlaceSearchRules.normalized(query)
            guard trimmed != PlaceSearchRules.normalized(oldValue) else { return }
            slowTimer?.cancel()
            // A direct search for the old text no longer matters.
            directSearch?.cancel()
            if trimmed.isEmpty {
                if isSearching { Log.app.info("Search cleared while waiting \(self.elapsed, privacy: .public)") }
                suggestions = []; suggestionsQuery = nil; message = nil; isSearching = false
                queryStarted = nil
            } else {
                // Keep the previous suggestions on screen while the new ones load.
                isSearching = true
                queryStarted = .now
                Log.app.info("Search asked: \(trimmed, privacy: .private)")
                slowTimer = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.slowAfter))
                    guard let self, !Task.isCancelled, self.isSearching else { return }
                    // Stop the spinner so the screen doesn't look stuck. Late results still show.
                    self.isSearching = false
                    self.message = "Search is taking a while, so your connection may be slow. You can clear the search and drag the map to drop a pin instead."
                    Log.app.info("Search slow: no response after \(Int(Self.slowAfter))s for \(trimmed, privacy: .private)")
                }
            }
            completer.queryFragment = trimmed
        }
    }
    @Published private(set) var suggestions: [PlaceSuggestion] = []
    /// The text `suggestions` answers. Nil until the completer answers.
    @Published private(set) var suggestionsQuery: String?
    /// Waiting on Apple for the current query.
    @Published private(set) var isSearching = false
    /// "No matches", "slow connection" or a network error, shown under the search field.
    @Published private(set) var message: String?

    private static let slowAfter: Double = 8
    private nonisolated static let noMatches = "No matches. Try the full name, or move the map to drop a pin."
    private let completer = MKLocalSearchCompleter()
    private var slowTimer: Task<Void, Never>?
    private var directSearch: MKLocalSearch?
    /// When the current query was sent, to log how long Apple took.
    private var queryStarted: Date?

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
        return Self.result(item, name: suggestion.title, address: suggestion.subtitle)
    }

    /// One plain search for `text`, for when the type-ahead hasn't answered. Returns the top match,
    /// or nil if there's none, it failed, or the search field has changed since (the message
    /// under the field says why when it's still relevant).
    func searchDirectly(_ text: String) async -> PlaceResult? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = completer.region
        request.resultTypes = [.pointOfInterest, .address]
        let search = MKLocalSearch(request: request)
        directSearch?.cancel()
        directSearch = search
        let started = Date.now
        Log.app.info("Search direct: started for \(text, privacy: .private)")
        defer { if directSearch === search { directSearch = nil } }
        do {
            let response = try await search.start()
            Log.app.info("Search direct: \(response.mapItems.count) results after \(Self.seconds(since: started), privacy: .public)")
            guard PlaceSearchRules.shouldApplyDirectResult(searched: text, current: query) else {
                Log.app.info("Search direct: field changed, result dropped")
                return nil
            }
            guard let item = response.mapItems.first else {
                message = Self.noMatches
                return nil
            }
            return Self.result(item, name: text, address: nil)
        } catch {
            Log.app.error("Search direct failed after \(Self.seconds(since: started), privacy: .public): \(Self.describe(error), privacy: .public)")
            if PlaceSearchRules.shouldApplyDirectResult(searched: text, current: query) {
                slowTimer?.cancel()
                isSearching = false
                message = Self.failureMessage(error)
            }
            return nil
        }
    }

    private static func result(_ item: MKMapItem, name: String, address: String?) -> PlaceResult {
        let name = item.name ?? name
        if #available(iOS 26, *) {
            return PlaceResult(name: name, address: item.address?.shortAddress ?? address,
                               coordinate: item.location.coordinate)
        } else {
            return PlaceResult(name: name, address: item.placemark.title ?? address,
                               coordinate: item.placemark.coordinate)
        }
    }

    fileprivate nonisolated static func failureMessage(_ error: Error) -> String {
        (error as? MKError)?.code == .placemarkNotFound
            ? noMatches
            : "Search isn't available right now (\(error.localizedDescription)). You can still move the map to drop a pin."
    }

    /// "MKErrorDomain 1: …", so the code shows in logs even when the description is vague.
    fileprivate nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }

    private static func seconds(since start: Date?) -> String {
        guard let start else { return "?s" }
        return String(format: "%.1fs", Date.now.timeIntervalSince(start))
    }

    private var elapsed: String { Self.seconds(since: queryStarted) }
}

extension PlaceSearch: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let fragment = completer.queryFragment
        let rows = completer.results.map {
            PlaceSuggestion(title: $0.title, subtitle: $0.subtitle, completion: $0)
        }
        Task { @MainActor in
            guard !PlaceSearchRules.normalized(self.query).isEmpty else { return }
            Log.app.info("Search results: \(rows.count) after \(self.elapsed, privacy: .public) for \(fragment, privacy: .private)")
            self.slowTimer?.cancel()
            self.isSearching = false
            self.suggestions = rows
            self.suggestionsQuery = fragment
            self.message = rows.isEmpty ? Self.noMatches : nil
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        let fragment = completer.queryFragment
        let text = Self.failureMessage(error)
        let detail = Self.describe(error)
        Task { @MainActor in
            Log.app.error("Search failed after \(self.elapsed, privacy: .public): \(detail, privacy: .public)")
            self.slowTimer?.cancel()
            self.isSearching = false
            self.suggestions = []
            self.suggestionsQuery = fragment
            self.message = text
        }
    }
}
