import FamilyControls
import SwiftUI

/// Where you set things up once: which apps are blocked, and the places where they unblock.
struct RulesView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var sync = SyncEngine.shared
    @Binding var placeSheet: PlaceSheet?
    @Binding var showPicker: Bool
    @State private var showInfo = false

    var body: some View {
        NavigationStack {
            List {
                if model.inSetupWindow { setupWindow }
                blockedApps
                places
                if sync.isAvailable || Self.hasDebug { settings }
            }
            .calmList()
            .navigationTitle("Spots")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("How the 24-hour wait works", systemImage: "info.circle") { showInfo = true }
                }
            }
            .sheet(isPresented: $showInfo) { WaitInfoSheet() }
        }
    }

    // MARK: Setup window

    @State private var confirmFinish = false
    @Environment(\.dynamicTypeSize) private var typeSize

    /// One slim row while the first 24 h are open. With accessibility text sizes, Finish goes
    /// under the label.
    private var setupWindow: some View {
        Section {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout())
            layout {
                Label("Setup · \(model.setupEndsAt.shortTimeLeft) left", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
                if !typeSize.isAccessibilitySize { Spacer() }
                Button("Finish") { confirmFinish = true }
                    .confirmationDialog("Finish setup?", isPresented: $confirmFinish, titleVisibility: .visible) {
                        Button("Finish setup") { model.finishSetup() }
                    } message: {
                        Text("From now on, new places and bigger areas take 24 hours to start working. This can't be undone.")
                    }
            }
        } footer: {
            Text("Changes apply right away until setup ends.")
        }
        .calmRows()
    }

    // MARK: Blocked apps

    private var blockedApps: some View {
        Section {
            if model.blockList.isEmpty {
                Text("No apps blocked yet.").foregroundStyle(.secondary)
            }
            let pending = model.blockList.pendingRemovals
            #if !SCREEN_TIME
            // Simulated build: names from the stand-in list.
            ForEach(model.blockList.simulatedApps, id: \.self) { name in
                BlockedRow(removeAt: pending.simulated[name],
                           remove: { model.blockList.simulatedApps.removeAll { $0 == name } },
                           keep: { model.keepBlocked(app: name) }) {
                    Label(name, systemImage: SimulatedApps.symbol(for: name))
                }
            }
            #endif

            // Real Screen Time build: opaque tokens. `Label(token)` draws the real icon and name.
            ForEach(Array(model.blockList.selection.applicationTokens), id: \.self) { token in
                BlockedRow(removeAt: pending.apps[token],
                           remove: { model.blockList.selection.applicationTokens.remove(token) },
                           keep: { model.keepBlocked(token: token) }) { Label(token) }
            }
            ForEach(Array(model.blockList.selection.categoryTokens), id: \.self) { token in
                BlockedRow(removeAt: pending.categories[token],
                           remove: { model.blockList.selection.categoryTokens.remove(token) },
                           keep: { model.keepBlocked(category: token) }) { Label(token) }
            }
            ForEach(Array(model.blockList.selection.webDomainTokens), id: \.self) { token in
                BlockedRow(removeAt: pending.webDomains[token],
                           remove: { model.blockList.selection.webDomainTokens.remove(token) },
                           keep: { model.keepBlocked(webDomain: token) }) { Label(token) }
            }

            Button(model.blockList.isEmpty ? "Choose apps to block" : "Add or remove apps",
                   systemImage: "plus") { showPicker = true }
                .disabled(model.screenTimeAccess != .approved)
        } header: {
            Text("Blocked apps")
        } footer: {
            Text(ShieldManager.isSimulated
                 ? "Blocked everywhere except your places. Swipe left to remove one."
                 : "Blocked everywhere except your places. Swipe left to remove one.\n\(Brand.websiteTip)")
        }
        .calmRows()
    }

    // MARK: Places

    private var places: some View {
        Section {
            ForEach(model.places) { place in
                Button { placeSheet = .edit(place) } label: {
                    PlaceRow(place: place, isHere: place.id == model.activePlace?.id)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain) // keep row text black/gray instead of tinted
            }
            .onDelete(perform: model.deletePlaces)

            ForEach(model.placeSlots, id: \.self) { slot in
                Button { placeSheet = .fill(slot: slot) } label: {
                    HStack(spacing: 12) {
                        PlaceIcon(symbol: Place.symbol(for: slot))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slot).foregroundStyle(.primary)
                            Text("Set location").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: model.deleteSlots)

            Button("Add place", systemImage: "plus") { placeSheet = .add }
                .disabled(model.places.count >= GeofenceMonitor.maxPlaces)
        } header: {
            Text("Places")
        } footer: {
            Text("Apps unblock while you're at one of these.")
        }
        .calmRows()
    }

    // MARK: Settings

    private var settings: some View {
        Section("Settings") {
            if sync.isAvailable {
                NavigationLink { BackupView() } label: {
                    LabeledContent {
                        Text(BackupView.statusText(sync))
                            .foregroundStyle(BackupView.isProblem(sync) ? Theme.waiting : .secondary)
                            .lineLimit(1)
                    } label: {
                        Label("Backup", systemImage: "icloud")
                    }
                }
            }
            #if DEBUG
            NavigationLink { DebugView() } label: {
                Label("Debug", systemImage: "ladybug")
            }
            #endif
        }
        .calmRows()
    }

    /// The Debug screen exists only in Debug builds.
    private static var hasDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

/// The 24-hour rules in one place, instead of repeated in every footer.
private struct WaitInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.medium) {
                Text("Some changes wait 24 hours, so you can't unblock apps on a whim.")
                    .font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 12) {
                    Label("Removing a blocked app", systemImage: "app.badge")
                    Label("Adding a new place", systemImage: "mappin")
                    Label("Making a place's area bigger", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .foregroundStyle(.secondary)
                Text("During your first 24 hours (setup), every change applies right away.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(Theme.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .calmBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct PlaceRow: View {
    let place: Place
    let isHere: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            PlaceIcon(symbol: place.symbol)
            // With accessibility text sizes the status goes under the name, so the name keeps
            // the row's width instead of breaking inside words.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).foregroundStyle(.primary)
                    Text([place.address, "\(Int(place.radius)) m"].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.secondary)
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                if let starts = place.activeAfter, !place.isActive() {
                    Countdown(meaning: "Starts in", until: starts)
                } else if isHere {
                    Text("Here").font(.footnote).foregroundStyle(.secondary)
                } else if let change = place.pendingChange {
                    Countdown(meaning: "New area in", until: change.appliesAt)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
    }
}

/// One blocked app. Swipe to remove it (which may wait 24 h), or to cancel a waiting removal.
private struct BlockedRow<Content: View>: View {
    let removeAt: Date?
    let remove: () -> Void
    let keep: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            content
            Spacer()
            if let removeAt {
                Countdown(meaning: "Unblocks in", until: removeAt)
            }
        }
        .swipeActions(edge: .trailing) {
            if removeAt == nil {
                // Not `.destructive`: during the delay the row stays put, and a destructive
                // action would animate it away first.
                Button("Remove", systemImage: "minus.circle", action: remove).tint(.red)
            } else {
                Button("Keep blocked", systemImage: "lock.fill", action: keep).tint(.accentColor)
            }
        }
    }
}

/// A 24 h wait. The only orange in the app.
/// A 24 h wait in a row: a clock and the time left ("23 h"). VoiceOver reads the full phrase.
/// Plain views, not a `Label`: inside a List row iOS restyled the Label as a row label of its
/// own, dropping the text and padding the row to about 2.5 times its height.
private struct Countdown: View {
    /// "Starts in", "New area in", "Unblocks in".
    let meaning: String
    let until: Date

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
            Text(until.shortTimeLeft)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.waiting)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(meaning) \(until.shortTimeLeft)")
    }
}

/// A place's symbol.
private struct PlaceIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 28)
    }
}
