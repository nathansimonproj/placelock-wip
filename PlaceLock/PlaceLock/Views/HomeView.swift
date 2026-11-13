import CoreLocation
import MapKit
import SwiftUI

/// Where you stand right now: locked, or unlocked at one of your places.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: LocationService
    @Binding var placeSheet: PlaceSheet?
    var showRules: () -> Void

    @State private var shieldPreviewApp: String?
    @State private var openedWhileUnlocked: String?
    /// Live GPS fix while Home is on screen, for the "Estimated location" line. Display only:
    /// the lock state comes from geofences either way.
    @State private var here: CLLocation?
    @State private var address: String?
    @State private var addressFix: CLLocation?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if model.screenTimeAccess != .approved || !location.hasAlways { setupCard }
                    statusCard
                    #if DEBUG
                    simulateCard
                    #endif
                    unlocksAt
                    if ShieldManager.isSimulated { testModeCard }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("PlaceLock")
            .task(id: location.authorization) { await followLocation() }
            .sheet(item: $shieldPreviewApp) { MockShieldView(appName: $0) }
            .alert("\(openedWhileUnlocked ?? "") would open normally",
                   isPresented: .init(get: { openedWhileUnlocked != nil }, set: { if !$0 { openedWhileUnlocked = nil } })) {
                Button("OK") {}
            } message: {
                Text("You're unlocked at \(model.activePlace?.name ?? "an allowed place").")
            }
        }
    }

    // MARK: Status

    private var statusCard: some View {
        let place = model.activePlace
        let tint: Color = place == nil ? .secondary : .green
        return VStack(spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.15)).frame(width: 120, height: 120)
                Image(systemName: place == nil ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(place == nil ? Color.primary : Color.green)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.top, 8)
            .overlay(alignment: .topTrailing) {
                if model.simulatedSpot != nil {
                    Label("Simulated", systemImage: "location.slash.fill")
                        .font(.caption.bold()).foregroundStyle(.purple)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.purple.opacity(0.12), in: Capsule())
                        .offset(x: 70)
                }
            }

            VStack(spacing: 6) {
                Text(place == nil ? "Locked" : "Unlocked").font(.largeTitle.bold())
                if let place {
                    Label("at \(place.name)", systemImage: place.symbol)
                        .font(.headline).foregroundStyle(.green)
                }
                Label("Estimated location: \(estimatedLocation)", systemImage: "location.fill")
                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text(statusDetail)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let message = model.message {
                Text(message)
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if place != nil {
                Button("Lock until I leave", systemImage: "lock.fill", role: .destructive) {
                    model.lockUntilLeave()
                }
                .buttonStyle(.bordered).controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
        .animation(.default, value: place?.id)
    }

    /// e.g. "4700 Brooklyn Ave NE (±8 m)". Coordinates until the address lookup comes back.
    private var estimatedLocation: String {
        guard location.authorization == .authorizedAlways || location.authorization == .authorizedWhenInUse else {
            return "location access off"
        }
        guard let here else { return "finding…" }
        let place = address ?? String(format: "%.5f, %.5f", here.coordinate.latitude, here.coordinate.longitude)
        return "\(place) (±\(Int(here.horizontalAccuracy.rounded())) m)"
    }

    /// Follows GPS while Home is on screen. Skips tiny changes so the card doesn't redraw every
    /// second, and looks up the street address again after moving about 25 m (Apple rate-limits lookups).
    private func followLocation() async {
        guard location.authorization == .authorizedAlways || location.authorization == .authorizedWhenInUse else {
            here = nil
            return
        }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                guard let fix = update.location, fix.horizontalAccuracy >= 0 else { continue }
                if let here, fix.distance(from: here) < 3,
                   abs(fix.horizontalAccuracy - here.horizontalAccuracy) < 3 { continue }
                here = fix
                if addressFix.map({ fix.distance(from: $0) >= 25 }) ?? true {
                    addressFix = fix
                    address = await Self.streetAddress(at: fix) ?? address
                }
            }
        } catch {
            Log.app.error("Live location stopped: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func streetAddress(at fix: CLLocation) async -> String? {
        if #available(iOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: fix),
                  let item = try? await request.mapItems.first else { return nil }
            return item.address?.shortAddress ?? item.address?.fullAddress
        } else {
            guard let mark = try? await CLGeocoder().reverseGeocodeLocation(fix).first else { return nil }
            let street = [mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " ")
            return street.isEmpty ? mark.name : street
        }
    }

    private var statusDetail: String {
        if model.isUnlocked { return "Your apps are available. They lock again when you leave." }
        if model.blockList.isEmpty { return "Choose apps to block in Rules." }
        if model.places.isEmpty { return "Add a place in Rules. Apps unblock on their own while you're there." }
        let count = ShieldManager.isSimulated ? model.blockList.simulatedApps.count : nil
        let what = count.map { "\($0) app\($0 == 1 ? "" : "s")" } ?? "Your apps"
        return "\(what) blocked. They unblock on their own when you arrive at one of your places."
    }

    // MARK: Places

    private var unlocksAt: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Unlocks at").font(.headline)
                Spacer()
                Button("Edit", action: showRules).font(.subheadline)
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.places) { place in
                        let here = place.id == model.activePlace?.id
                        let waiting = !place.isActive()
                        Button { placeSheet = .edit(place) } label: {
                            Label(waiting ? "\(place.name) · \(place.activeAfter?.shortTimeLeft ?? "")" : place.name,
                                  systemImage: waiting ? "clock" : place.symbol)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .foregroundStyle(here ? .white : waiting ? .secondary : .primary)
                                .background(here ? Color.green : Color(.secondarySystemGroupedBackground),
                                            in: Capsule())
                        }
                    }
                    ForEach(model.placeSlots, id: \.self) { slot in
                        Button { placeSheet = .fill(slot: slot) } label: {
                            Label("\(slot) · Set location", systemImage: Place.symbol(for: slot))
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .foregroundStyle(.orange)
                                .overlay(Capsule().strokeBorder(.orange, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                        }
                    }
                    if model.places.isEmpty && model.placeSlots.isEmpty {
                        Button("Add a place", systemImage: "plus") { placeSheet = .add }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: Simulate location (debug builds only)

    #if DEBUG
    private var simulateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Pretend I'm at…", systemImage: "location.viewfinder")
                    .font(.headline).foregroundStyle(.purple)
                Text(model.simulatedSpot == nil
                     ? "Using real location. Pick a spot to see how the app reacts."
                     : "Real location is ignored until you tap Real location.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    simChip("Real location", symbol: "location.fill", spot: nil)
                    ForEach(model.places) { place in
                        simChip(place.name, symbol: place.symbol, spot: .place(place.id))
                    }
                    simChip("Somewhere else", symbol: "figure.walk", spot: .elsewhere)
                    if model.places.contains(where: { $0.activeAfter != nil || $0.pendingChange != nil })
                        || !model.blockList.pendingRemovals.isEmpty {
                        Button { model.skipDelays() } label: {
                            Label("Skip 24 h wait", systemImage: "forward.fill")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(.orange)
                                .background(.orange.opacity(0.15), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.purple.opacity(0.3), lineWidth: 1))
    }

    private func simChip(_ title: String, symbol: String, spot: AppModel.SimulatedSpot?) -> some View {
        let selected = model.simulatedSpot == spot
        return Button { model.simulatedSpot = spot } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(selected ? .white : .primary)
                .background(selected ? Color.purple : Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: Setup

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.screenTimeAccess == .turnedOff ? "Blocking is off" : "Finish setup",
                  systemImage: "exclamationmark.circle.fill")
                .font(.headline).foregroundStyle(.orange)
            if !location.hasAlways {
                Text("PlaceLock needs location set to Always so it can unblock apps when you arrive and lock them when you leave.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button(location.authorization == .notDetermined ? "Allow location access" : "Set location to Always") {
                    if location.authorization == .denied || location.authorization == .restricted
                        || location.authorization == .authorizedWhenInUse {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    } else {
                        location.requestPermission()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            if model.screenTimeAccess == .turnedOff {
                Text("Screen Time access was turned off in Settings, so PlaceLock can't block apps right now.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if model.screenTimeAccess != .approved {
                Button(model.screenTimeAccess == .turnedOff ? "Turn Screen Time access back on" : "Allow Screen Time access") {
                    Task {
                        do {
                            try await ShieldManager.requestAuthorization()
                        } catch {
                            model.message = "Screen Time access failed: \(error.localizedDescription)"
                        }
                        await model.reconcile() // re-reads access and puts the block back on
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Test mode (free developer account only)

    private var testModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("**Test mode.** Blocking is simulated until the paid developer account.")
                    .font(.footnote).foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "testtube.2").foregroundStyle(.orange)
            }
            if !model.blockList.isEmpty {
                Menu {
                    ForEach(model.blockList.simulatedApps, id: \.self) { name in
                        Button(name, systemImage: SimulatedApps.symbol(for: name)) {
                            if model.isUnlocked { openedWhileUnlocked = name } else { shieldPreviewApp = name }
                        }
                    }
                } label: {
                    Label("Try opening a blocked app", systemImage: "hand.tap").font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }
}
