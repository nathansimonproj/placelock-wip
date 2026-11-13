import FamilyControls
import SwiftUI

/// The rules: which apps are blocked, and the allowlist of places where they unblock on their own.
struct RulesView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var sync = SyncEngine.shared
    @Binding var placeSheet: PlaceSheet?
    @Binding var showPicker: Bool

    var body: some View {
        NavigationStack {
            List {
                if model.inSetupWindow { setupWindow }
                blockedApps
                allowlist
                if sync.isEnabled { backup }
            }
            .navigationTitle("Rules")
        }
    }

    // MARK: Backup

    private var backup: some View {
        Section {
            Label(backupText, systemImage: backupSymbol)
                .foregroundStyle(backupIsProblem ? .orange : .secondary)
        } header: {
            Text("Backup")
        } footer: {
            Text("Places and unlock history are backed up to your account. Blocked apps stay on this phone.")
        }
    }

    private var backupText: String {
        let pending = sync.pendingCount > 0 ? " · \(sync.pendingCount) waiting" : ""
        switch sync.status {
        case .off: return "Off"
        case .idle, .syncing: return "Backing up…" + pending
        case .synced(let date): return "Backed up \(date.formatted(.relative(presentation: .named)))" + pending
        case .failed(let reason): return "Not backed up: \(reason)" + pending
        }
    }

    private var backupSymbol: String {
        switch sync.status {
        case .failed: "exclamationmark.icloud"
        case .synced: "checkmark.icloud"
        default: "icloud"
        }
    }

    private var backupIsProblem: Bool {
        if case .failed = sync.status { true } else { false }
    }

    // MARK: Setup window

    @State private var confirmFinish = false

    private var setupWindow: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Setup window · \(model.setupEndsAt.shortTimeLeft) left", systemImage: "hourglass")
                    .font(.headline).foregroundStyle(.indigo)
                Text("Changes apply right away for now. After setup, new places and bigger areas take 24 hours to start working.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            Button("Finish setup now", systemImage: "checkmark.seal") { confirmFinish = true }
                .confirmationDialog("Finish setup?", isPresented: $confirmFinish, titleVisibility: .visible) {
                    Button("Finish setup") { model.finishSetup() }
                } message: {
                    Text("From now on, new places and bigger areas take 24 hours to start working. This can't be undone.")
                }
        }
    }

    // MARK: Blocked apps

    private var blockedApps: some View {
        Section {
            if model.blockList.isEmpty {
                Text("No apps blocked yet.").foregroundStyle(.secondary)
            }
            // Simulated build: names from the stand-in list.
            let pending = model.blockList.pendingRemovals
            ForEach(model.blockList.simulatedApps, id: \.self) { name in
                BlockedRow(removeAt: pending.simulated[name],
                           remove: { model.blockList.simulatedApps.removeAll { $0 == name } },
                           keep: { model.keepBlocked(app: name) }) {
                    Label(name, systemImage: SimulatedApps.symbol(for: name))
                }
            }

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
                   systemImage: "plus.circle.fill") { showPicker = true }
                .disabled(model.screenTimeAccess != .approved)
        } header: {
            Text("Blocked apps")
        } footer: {
            Text(model.inSetupWindow
                 ? "Blocked everywhere except the places below. Swipe left to remove one."
                 : "Blocked everywhere except the places below. Removing an app takes 24 hours, so you can't unblock one on a whim.")
        }
    }

    // MARK: Allowlist

    private var allowlist: some View {
        Section {
            ForEach(model.places) { place in
                Button { placeSheet = .edit(place) } label: {
                    PlaceRow(place: place, isHere: place.id == model.activePlace?.id)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain) // keep row text black/gray instead of tinted blue
            }
            .onDelete(perform: model.deletePlaces)

            ForEach(model.placeSlots, id: \.self) { slot in
                Button { placeSheet = .fill(slot: slot) } label: {
                    HStack(spacing: 12) {
                        PlaceIcon(symbol: Place.symbol(for: slot), tint: .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slot).foregroundStyle(.primary)
                            Text("Set location").font(.footnote).foregroundStyle(.orange)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: model.deleteSlots)

            Button("Add place", systemImage: "plus.circle.fill") { placeSheet = .add }
                .disabled(model.places.count >= GeofenceMonitor.maxPlaces)
        } header: {
            Text("Allowlist")
        } footer: {
            Text(model.inSetupWindow
                 ? "Apps unblock on their own while you're at one of these and lock again when you leave. Tap a place to edit it."
                 : "Apps unblock on their own while you're at one of these. New places and bigger areas take 24 hours to start working, so you can't add one on the spot."
            )
        }
    }
}

private struct PlaceRow: View {
    let place: Place
    let isHere: Bool

    var body: some View {
        HStack(spacing: 12) {
            PlaceIcon(symbol: place.symbol, tint: isHere ? .green : place.isActive() ? .accentColor : .gray)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(.primary)
                Text([place.address, "\(Int(place.radius)) m"].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let starts = place.activeAfter, !place.isActive() {
                Badge(text: "Starts in \(starts.shortTimeLeft)", symbol: "clock", tint: .orange)
            } else if isHere {
                Badge(text: "Here now", symbol: nil, tint: .green)
            } else if let change = place.pendingChange {
                Badge(text: "New area in \(change.appliesAt.shortTimeLeft)", symbol: "clock", tint: .orange)
            }
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
                Badge(text: "Unblocks in \(removeAt.shortTimeLeft)", symbol: "clock", tint: .orange)
            }
        }
        .swipeActions(edge: .trailing) {
            if removeAt == nil {
                // Not `.destructive`: during the delay the row stays put, and a destructive
                // action would animate it away first.
                Button("Remove", systemImage: "minus.circle", action: remove).tint(.red)
            } else {
                Button("Keep blocked", systemImage: "lock.fill", action: keep).tint(.blue)
            }
        }
    }
}

private struct Badge: View {
    let text: String
    let symbol: String?
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.bold()).foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tint.opacity(0.15), in: Capsule())
        .fixedSize()
    }
}

private struct PlaceIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(tint, in: RoundedRectangle(cornerRadius: 9))
    }
}
