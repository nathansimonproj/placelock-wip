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
        // iOS's own tab bar is hidden: its selected pill can't be recolored, and on the locked
        // gradient it washed out the white label. `CalmTabBar` draws ours.
        TabView(selection: $tab) {
            HomeView(placeSheet: $placeSheet, showRules: { tab = .rules })
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom, spacing: 0) { CalmTabBar.space }
                .tag(Tab.home)
            RulesView(placeSheet: $placeSheet, showPicker: $showPicker)
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom, spacing: 0) { CalmTabBar.space }
                .tag(Tab.rules)
        }
        // One bar over both tabs, so the pill slides between them. Each tab keeps room for it
        // (`CalmTabBar.space`); a safe-area inset on the TabView itself doesn't reach the tabs.
        .overlay(alignment: .bottom) { CalmTabBar(tab: $tab) }
        .sheet(item: $placeSheet) { sheet in
            switch sheet {
            case .add: AddPlaceView()
            case .fill(let slot): AddPlaceView(slot: slot)
            case .edit(let place): AddPlaceView(editing: place)
            }
        }
        .blockedAppPicker(isPresented: $showPicker, model: model)
        // First-run setup. It asks for location, Screen Time and notifications with the reason on screen.
        .fullScreenCover(isPresented: .init(get: { !model.hasOnboarded }, set: { _ in })) {
            OnboardingView()
        }
        #if DEBUG
        // Launch with `-sheet add` to open Add place directly (for screenshots).
        .onAppear { if UserDefaults.standard.string(forKey: "sheet") == "add" { placeSheet = .add } }
        #endif
    }
}

/// Home and Rules in one floating capsule. The selected tab is a dark sage pill with a white
/// label (about 7:1 contrast), so it reads on both the locked and the unlocked gradient.
struct CalmTabBar: View {
    @Binding var tab: RootView.Tab
    @EnvironmentObject private var model: AppModel

    /// Room each tab leaves at the bottom: the 50 pt items, 5 pt padding on each side and the
    /// gap below the bar.
    static var space: some View { Color.clear.frame(height: 50 + 10 + Theme.small) }

    private var unlocked: Bool { model.activePlace != nil }
    private let sage = Color(uiColor: Brand.accent.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))

    var body: some View {
        HStack(spacing: 4) {
            item(.home, "Home", symbol: "house.fill")
            item(.rules, "Rules", symbol: "slider.horizontal.3")
        }
        .padding(5)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(unlocked ? Color.white.opacity(0.35) : Color.black.opacity(0.25)))
                .overlay(Capsule().strokeBorder(.white.opacity(unlocked ? 0.6 : 0.12)))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        }
        .environment(\.colorScheme, unlocked ? .light : .dark)
        .padding(.bottom, Theme.small)
        .animation(Theme.motion, value: tab)
        .animation(.smooth(duration: 1.2), value: unlocked)
    }

    private func item(_ target: RootView.Tab, _ title: String, symbol: String) -> some View {
        let selected = tab == target
        return Button { tab = target } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                Text(title).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(width: 86, height: 50)
            .background { if selected { Capsule().fill(sage) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension View {
    /// Choosing apps to block: Apple's picker in Screen Time builds, the stand-in list otherwise.
    @ViewBuilder
    func blockedAppPicker(isPresented: Binding<Bool>, model: AppModel) -> some View {
        #if SCREEN_TIME
        familyActivityPicker(isPresented: isPresented,
                             selection: Binding(get: { model.blockList.selection },
                                                set: { model.blockList.selection = $0 }))
        #else
        sheet(isPresented: isPresented) { SimulatedAppPicker().environmentObject(model) }
        #endif
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
