import FamilyControls
import SwiftUI

/// Which place sheet is open: a new place, filling a slot like "Home", or editing a place.
enum PlaceSheet: Identifiable {
    case add
    case fill(slot: String)
    case edit(Place)

    var id: String {
        switch self {
        case .add: "add"
        case .fill(let slot): "fill-\(slot)"
        case .edit(let place): "edit-\(place.id)"
        }
    }
}

/// Two tabs along the bottom: Home (where you stand) and Rules (what's blocked, where it unblocks).
/// The sheets live here so either tab can open them.
struct RootView: View {
    enum Tab: String { case home, rules }

    @EnvironmentObject private var model: AppModel
    // Launch with `-tab rules` to open on Rules (handy for screenshots).
    @State private var tab: Tab = Tab(rawValue: UserDefaults.standard.string(forKey: "tab") ?? "") ?? .home
    @State private var placeSheet: PlaceSheet?
    @State private var showPicker = false

    var body: some View {
        TabView(selection: $tab) {
            HomeView(placeSheet: $placeSheet, showRules: { tab = .rules })
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)
            RulesView(placeSheet: $placeSheet, showPicker: $showPicker)
                .tabItem { Label("Rules", systemImage: "slider.horizontal.3") }
                .tag(Tab.rules)
        }
        .sheet(item: $placeSheet) { sheet in
            switch sheet {
            case .add: AddPlaceView()
            case .fill(let slot): AddPlaceView(slot: slot)
            case .edit(let place): AddPlaceView(editing: place)
            }
        }
        #if SCREEN_TIME
        .familyActivityPicker(isPresented: $showPicker, selection: $model.blockList.selection)
        #else
        .sheet(isPresented: $showPicker) { SimulatedAppPicker() }
        #endif
        .task { model.requestNotificationPermission() }
        #if DEBUG
        // Launch with `-sheet add` to open Add place directly (for screenshots).
        .onAppear { if UserDefaults.standard.string(forKey: "sheet") == "add" { placeSheet = .add } }
        #endif
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
