import MapKit
import SwiftUI

/// Search for a place (or pan the map to drop a pin), set a radius and a name.
/// Also edits an existing place (`editing`) and fills an allowlist slot like "Home" (`slot`).
struct AddPlaceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = PlaceSearch()
    @FocusState private var searchFocused: Bool
    @FocusState private var nameFocused: Bool

    /// Set when filling an allowlist slot like "Home". The name starts as the slot name.
    private let slot: String?
    private let editing: Place?
    @State private var name: String
    @State private var nameFromSearch: String? // last name search filled in; a new pick replaces it unless edited
    @State private var address: String?
    @State private var radius: Double = 150
    @State private var center: CLLocationCoordinate2D?
    @State private var resolving = false
    /// A new place opens on where you are (iOS's last known location); editing opens on the place.
    /// Always a fixed region we set, never `.userLocation`: MapKit writes a following camera back
    /// into this binding, and that re-ran `body` forever (100% CPU, the sheet never appeared).
    @State private var camera: MapCameraPosition

    init(slot: String? = nil, editing: Place? = nil) {
        self.slot = slot
        self.editing = editing
        _name = State(initialValue: editing?.name ?? slot ?? "")
        _address = State(initialValue: editing?.address)
        _radius = State(initialValue: editing?.radius ?? 150)
        let start = editing?.coordinate ?? Self.whereYouAre
        _center = State(initialValue: start)
        _camera = State(initialValue: start.map(Self.region) ?? .automatic)
    }

    /// iOS keeps the phone's latest location for every app, so this is instant. Nil only if the
    /// phone has never had a location fix.
    private static var whereYouAre: CLLocationCoordinate2D? { CLLocationManager().location?.coordinate }

    private var title: String {
        if editing != nil { return "Edit place" }
        if let slot { return "Where's \(slot)?" }
        return "Add place"
    }

    private static func region(_ c: CLLocationCoordinate2D) -> MapCameraPosition {
        .region(MKCoordinateRegion(center: c, latitudinalMeters: 1000, longitudinalMeters: 1000))
    }

    private var showingSuggestions: Bool {
        searchFocused && !search.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                if showingSuggestions {
                    suggestionList
                } else {
                    details
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // No auto-focus on search: on a phone the keyboard would open over the map before you've seen it.
            .onAppear { if let center { search.bias(around: center) } }
            // Swiping down grabbed slider and map drags and closed the sheet without saving.
            // Cancel and Save are the only ways out.
            .interactiveDismissDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(trimmedName.isEmpty || center == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done", action: dismissKeyboard)
                }
            }
        }
    }

    // MARK: Pieces

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search for a place", text: $search.query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit(submitSearch)
                if resolving {
                    ProgressView()
                } else if !search.query.isEmpty {
                    Button { search.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            if let message = search.message, showingSuggestions || search.suggestions.isEmpty {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var suggestionList: some View {
        List {
            if search.isSearching {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Searching…").foregroundStyle(.secondary)
                }
            }
            ForEach(search.suggestions) { suggestion in
                Button { pick(suggestion) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title).foregroundStyle(.primary)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var mapArea: some View {
        ZStack {
            Map(position: $camera) {
                UserAnnotation()
                if let center {
                    MapCircle(center: center, radius: radius)
                        .foregroundStyle(Color(uiColor: Brand.accent).opacity(0.2))
                        .stroke(Color(uiColor: Brand.accent), lineWidth: 2)
                }
            }
            // The usual blue "you are here" dot (it takes the map's tint; sage blended into the pin).
            .tint(.blue)
            .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
            // .onEnd, not .continuous: update the circle once the drag settles.
            .onMapCameraChange(frequency: .onEnd) { context in
                center = context.region.center
                search.bias(around: context.region.center)
            }
            Image(systemName: "mappin")
                .font(.title).foregroundStyle(.tint)
                .offset(y: -14)
                .allowsHitTesting(false)
                .accessibilityHidden(true) // marks the map's center; the map itself is what VoiceOver reads
        }
        .overlay(alignment: .bottomTrailing) {
            // Back to where you are. Not MapKit's MapUserLocationButton: it switches the camera to
            // `.userLocation`, which loops (see `camera`).
            Button {
                guard let here = Self.whereYouAre else { return }
                center = here
                camera = Self.region(here)
            } label: {
                Image(systemName: "location.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            // The circle is a fixed 40 pt, so the arrow stops growing before it spills out.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(10)
            .accessibilityLabel("Go to my location")
        }
    }

    /// Map, name and radius in one scrolling form. The keyboard scrolls the form instead of
    /// squeezing the map: with a fixed-height form the map collapsed to nothing on a phone.
    private var details: some View {
        Form {
            Section {
                mapArea
                    .frame(height: 300)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("Search above, or drag the map so the pin sits on your spot.")
            }
            Section {
                TextField("Name (required, e.g. Library)", text: $name)
                    .focused($nameFocused)
                    .submitLabel(.done)
                if let address {
                    Label(address, systemImage: "mappin.and.ellipse")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                VStack(alignment: .leading) {
                    Text("Radius: \(Int(radius)) m")
                        .accessibilityHidden(true) // the slider reads it
                    Slider(value: $radius, in: 50...500, step: 25) { editing in
                        if editing { dismissKeyboard() }
                    }
                    .accessibilityLabel("Radius")
                    .accessibilityValue(SpokenRules.meters(radius))
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if radius < 100 {
                        Label("Small circles can miss you arriving, especially indoors.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if let delayNote {
                        Label(delayNote, systemImage: "clock")
                            .foregroundStyle(.orange)
                    }
                    Text("iOS notices you've left about 100–200 m past the edge, so keep the circle snug.")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Tells you up front whether saving will wait 24 h.
    private var delayNote: String? {
        if model.inSetupWindow { return nil }
        guard let editing else { return "New places start working 24 hours after you add them." }
        if let change = editing.pendingChange {
            return "An earlier change applies \(change.appliesAt.formatted(.relative(presentation: .named))). Saving a new area restarts the 24 hours."
        }
        guard let center, editing.isActive(),
              !editing.contains(center: center, radius: radius) else { return nil }
        return "Moving or enlarging a place takes effect in 24 hours. Until then the current area keeps working."
    }

    // MARK: Actions

    private func dismissKeyboard() {
        searchFocused = false
        nameFocused = false
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// The keyboard's Search key. Takes the top suggestion, or searches directly when Apple's
    /// type-ahead hasn't answered for this text (it can stall on a slow network).
    private func submitSearch() {
        switch PlaceSearchRules.onSubmit(query: search.query, suggestionsQuery: search.suggestionsQuery,
                                         suggestionCount: search.suggestions.count, busy: resolving) {
        case .nothing:
            break
        case .pickFirstSuggestion:
            if let first = search.suggestions.first { pick(first) }
        case .searchDirectly(let text):
            searchFocused = false
            resolving = true
            Task {
                defer { resolving = false }
                if let result = await search.searchDirectly(text) { use(result) }
            }
        }
    }

    private func pick(_ suggestion: PlaceSuggestion) {
        searchFocused = false
        resolving = true
        Task {
            defer { resolving = false }
            do {
                use(try await search.resolve(suggestion))
            } catch {
                Log.app.error("Search resolve failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Moves the pin to a search result and fills in the name unless you've typed your own.
    private func use(_ result: PlaceResult) {
        center = result.coordinate
        camera = Self.region(result.coordinate)
        address = result.address
        if trimmedName.isEmpty || name == nameFromSearch {
            name = result.name
            nameFromSearch = result.name
        }
        search.query = ""
        Log.app.info("Search picked \(result.name, privacy: .private) at \(result.coordinate.latitude, privacy: .private), \(result.coordinate.longitude, privacy: .private)")
    }

    private func save() {
        guard let center else { return }
        if let place = editing {
            model.editPlace(place.id, name: trimmedName, address: address, center: center, radius: radius)
            Log.app.info("Edited place \(trimmedName, privacy: .private) r=\(Int(radius))m")
            dismiss()
            return
        }
        let place = Place(name: trimmedName, address: address,
                          latitude: center.latitude, longitude: center.longitude, radius: radius)
        model.addPlace(place, fillingSlot: slot)
        Log.app.info("Added place \(place.name, privacy: .private) r=\(Int(place.radius))m at \(center.latitude, privacy: .private), \(center.longitude, privacy: .private)")
        dismiss()
    }
}
