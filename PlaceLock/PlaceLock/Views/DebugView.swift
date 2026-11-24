import SwiftUI

#if DEBUG
/// Developer tools (Debug builds only, so never in the App Store build), kept off Home: pretend
/// to be somewhere, skip the 24 h waits, and try the simulated block screen (free developer
/// account). Reached from Settings › General.
struct DebugView: View {
    @EnvironmentObject private var model: AppModel
    @State private var shieldPreviewApp: String?
    @State private var openedWhileUnlocked: String?

    var body: some View {
        List {
            engineSection
            simulate
            #if !SCREEN_TIME
            testMode
            #endif
        }
        .calmList()
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
        #if !SCREEN_TIME
        .sheet(item: $shieldPreviewApp) { MockShieldView(appName: $0) }
        .alert("\(openedWhileUnlocked ?? "") would open normally",
               isPresented: .init(get: { openedWhileUnlocked != nil }, set: { if !$0 { openedWhileUnlocked = nil } })) {
            Button("OK") {}
        } message: {
            Text("You're unlocked at \(model.activePlace?.name ?? "an allowed place").")
        }
        #endif
    }

    // MARK: Location engine (shadow mode)

    @State private var engineMode = AppModel.shared.engine.mode
    @State private var traceCleared = false

    private var engineSection: some View {
        Section {
            Picker("Decides", selection: $engineMode) {
                Text("Current (engine in shadow)").tag(LocationEngine.Mode.shadow)
                Text("New engine").tag(LocationEngine.Mode.live)
            }
            .onChange(of: engineMode) { _, mode in model.engine.mode = mode }
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tracking: \(model.engine.tracking.rawValue)")
                    ForEach(model.places) { place in
                        let state = model.engine.state(for: place)
                        Text("\(place.name): \(state?.presence.rawValue ?? "unknown")\(state?.reason.map { " (\($0.rawValue))" } ?? "")")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote.monospaced())
            }
            ShareLink(item: Trace.url) {
                Label("Export location trace (\(traceCleared ? "0 bytes" : Trace.sizeDescription))", systemImage: "square.and.arrow.up")
            }
            Button("Clear location trace", systemImage: "trash", role: .destructive) {
                Trace.clear()
                traceCleared = true
            }
        } header: {
            Text("Location engine")
        } footer: {
            Text("In shadow, the new engine tracks and records what it would do, and the current logic still blocks and unblocks. The trace stays on this phone unless you share it.")
        }
        .calmRows()
    }

    // MARK: Simulate location

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
                if model.simulatedSpot == spot {
                    Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(model.simulatedSpot == spot ? .isSelected : [])
    }

    // MARK: Test mode (simulated blocking, free build)

    #if !SCREEN_TIME
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
    #endif
}
#endif
