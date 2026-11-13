import SwiftUI

/// Developer tools, kept off Home: pretend to be somewhere (debug builds) and try the
/// simulated block screen (free developer account). Reached from Rules › Settings.
struct DebugView: View {
    @EnvironmentObject private var model: AppModel
    @State private var shieldPreviewApp: String?
    @State private var openedWhileUnlocked: String?

    /// True when this screen has anything to show in this build.
    static var isAvailable: Bool {
        #if DEBUG
        true
        #else
        ShieldManager.isSimulated
        #endif
    }

    var body: some View {
        List {
            #if DEBUG
            simulate
            #endif
            if ShieldManager.isSimulated { testMode }
        }
        .calmList()
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shieldPreviewApp) { MockShieldView(appName: $0) }
        .alert("\(openedWhileUnlocked ?? "") would open normally",
               isPresented: .init(get: { openedWhileUnlocked != nil }, set: { if !$0 { openedWhileUnlocked = nil } })) {
            Button("OK") {}
        } message: {
            Text("You're unlocked at \(model.activePlace?.name ?? "an allowed place").")
        }
    }

    // MARK: Simulate location

    #if DEBUG
    private var simulate: some View {
        Section {
            spotRow("Real location", symbol: "location", spot: nil)
            ForEach(model.places) { place in
                spotRow(place.name, symbol: place.symbol, spot: .place(place.id))
            }
            spotRow("Somewhere else", symbol: "figure.walk", spot: .elsewhere)
            if model.places.contains(where: { $0.activeAfter != nil || $0.pendingChange != nil })
                || !model.blockList.pendingRemovals.isEmpty {
                Button("Skip 24 h wait", systemImage: "forward") { model.skipDelays() }
            }
        } header: {
            Text("Pretend I'm at")
        } footer: {
            Text(model.simulatedSpot == nil
                 ? "Using real location. Pick a spot to see how the app reacts."
                 : "Real location is ignored until you pick Real location.")
        }
        .calmRows()
    }

    private func spotRow(_ title: String, symbol: String, spot: AppModel.SimulatedSpot?) -> some View {
        Button { model.simulatedSpot = spot } label: {
            HStack {
                Label(title, systemImage: symbol).foregroundStyle(.primary)
                Spacer()
                if model.simulatedSpot == spot { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
    #endif

    // MARK: Test mode

    private var testMode: some View {
        Section {
            if model.blockList.isEmpty {
                Text("Choose apps to block first.").foregroundStyle(.secondary)
            }
            ForEach(model.blockList.simulatedApps, id: \.self) { name in
                Button {
                    if model.isUnlocked { openedWhileUnlocked = name } else { shieldPreviewApp = name }
                } label: {
                    Label(name, systemImage: SimulatedApps.symbol(for: name)).foregroundStyle(.primary)
                }
            }
        } header: {
            Text("Try opening a blocked app")
        } footer: {
            Text("Test mode: blocking is simulated until the paid developer account.")
        }
        .calmRows()
    }
}
