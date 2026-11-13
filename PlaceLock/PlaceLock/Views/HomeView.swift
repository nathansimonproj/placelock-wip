import CoreLocation
import MapKit
import SwiftUI

/// Variant B, "Map": your places are the product, so Home is the map. Each place is a circle you
/// can see; a floating card says whether you're locked and how far the nearest place is.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: LocationService
    @Binding var placeSheet: PlaceSheet?
    var showRules: () -> Void

    /// `.automatic` frames every place and you.
    @State private var camera: MapCameraPosition = .automatic
    /// One fix when Home appears, for "0.4 mi away". Not a live stream: the lock state comes
    /// from geofences, and this line doesn't need to tick.
    @State private var here: CLLocation?

    var body: some View {
        ZStack(alignment: .bottom) {
            map
            VStack(spacing: Theme.small) {
                if needsFix { FixBanner().padding(.horizontal, Theme.medium) }
                Spacer()
                Toast()
                statusCard
            }
        }
        .animation(Theme.motion, value: model.activePlace?.id)
        .task(id: location.authorization) {
            guard location.authorization == .authorizedAlways || location.authorization == .authorizedWhenInUse
            else { return }
            here = try? await location.currentLocation(maxAccuracy: 1000)
        }
    }

    private var needsFix: Bool { !location.hasAlways || model.screenTimeAccess != .approved }

    // MARK: Map

    private var map: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(model.places) { place in
                let isHere = place.id == model.activePlace?.id
                // Explicit color: MapKit draws `.accentColor` as system blue.
                let tint: Color = place.isActive() ? Color(uiColor: Brand.accent) : .gray
                MapCircle(center: place.coordinate, radius: place.radius)
                    .foregroundStyle(tint.opacity(isHere ? 0.35 : 0.18))
                    .stroke(tint, lineWidth: 2)
                Annotation(place.name, coordinate: place.coordinate, anchor: .center) {
                    Image(systemName: place.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(tint))
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                        .onTapGesture { placeSheet = .edit(place) }
                }
            }
        }
        // Muted map: no shop and restaurant pins competing with your places.
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }

    // MARK: Status card

    private var statusCard: some View {
        let place = model.activePlace
        let unlocked = place != nil
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(unlocked ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(unlocked ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.14))))
                VStack(alignment: .leading, spacing: 2) {
                    Text(unlocked ? "Unlocked" : "Locked")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            if unlocked {
                Button { model.lockUntilLeave() } label: {
                    Label("Lock until I leave", systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if model.blockList.isEmpty {
                Button("Choose apps to block", systemImage: "plus", action: showRules)
                    .font(.subheadline.weight(.semibold))
            }

            placeChips
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, Theme.small + 4)
        .padding(.bottom, Theme.small)
    }

    private var subtitle: String {
        if let place = model.activePlace { return "at \(place.name). Apps lock again when you leave." }
        if model.places.isEmpty { return "Add a place to unlock your apps there." }
        if let nearest { return "\(nearest.place.name) is \(nearest.distance) away" }
        let working = model.places.filter { $0.isActive() }.map(\.name)
        return working.isEmpty ? "No places working yet" : "Opens at \(Brand.list(working))"
    }

    /// The closest working place and how far its edge is, e.g. ("Library", "0.3 mi").
    private var nearest: (place: Place, distance: String)? {
        guard let here else { return nil }
        let best = model.places.filter { $0.isActive() }.min { $0.distanceOutside(here) < $1.distanceOutside(here) }
        guard let best else { return nil }
        let meters = max(0, best.distanceOutside(here))
        let text = Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
        return (best, text)
    }

    /// Tap a place to fly the map to it; the + adds one.
    private var placeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.small) {
                ForEach(model.places) { place in
                    let isHere = place.id == model.activePlace?.id
                    let waiting = !place.isActive()
                    Button {
                        withAnimation(.smooth(duration: 0.6)) {
                            camera = .region(MKCoordinateRegion(center: place.coordinate,
                                                                latitudinalMeters: place.radius * 8,
                                                                longitudinalMeters: place.radius * 8))
                        }
                    } label: {
                        Label(waiting ? "\(place.name) · \(place.activeAfter?.shortTimeLeft ?? "")" : place.name,
                              systemImage: waiting ? "clock" : place.symbol)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .foregroundStyle(isHere ? AnyShapeStyle(.white) : waiting ? AnyShapeStyle(Theme.waiting) : AnyShapeStyle(.primary))
                            .background(Capsule().fill(isHere ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.tertiarySystemFill))))
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { placeSheet = .edit(place) }
                    }
                }
                ForEach(model.placeSlots, id: \.self) { slot in
                    Button { placeSheet = .fill(slot: slot) } label: {
                        Label("\(slot) · set", systemImage: Place.symbol(for: slot))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .foregroundStyle(.secondary)
                            .overlay(Capsule().strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                }
                Button { placeSheet = .add } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(.tint)
                        .background(Capsule().fill(Color(.tertiarySystemFill)))
                }
                .disabled(model.places.count >= GeofenceMonitor.maxPlaces)
                .accessibilityLabel("Add place")
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Pieces

/// One line when blocking can't work: a skipped setup step or access turned off in Settings.
struct FixBanner: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: LocationService

    var body: some View {
        Button(action: fix) {
            HStack(spacing: Theme.small) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.waiting)
                Text(text).foregroundStyle(.primary)
                Spacer()
                Text("Fix").fontWeight(.semibold).foregroundStyle(.tint)
            }
            .font(.subheadline)
            .padding(.horizontal, Theme.medium)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
    }

    private var text: String {
        if model.screenTimeAccess != .approved {
            return model.screenTimeAccess == .turnedOff ? "Blocking is off" : "Screen Time access needed"
        }
        return "Location isn't set to Always"
    }

    private func fix() {
        if model.screenTimeAccess != .approved {
            Task {
                do {
                    try await ShieldManager.requestAuthorization()
                } catch {
                    model.message = "Screen Time access failed: \(error.localizedDescription)"
                }
                await model.reconcile()
            }
        } else if location.authorization == .notDetermined {
            location.requestPermission()
        } else {
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        }
    }
}

/// `model.message` for 3 s, then it fades.
struct Toast: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let message = model.message {
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.medium)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.horizontal, Theme.large)
                    .transition(.opacity)
                    .onTapGesture { model.message = nil }
            }
        }
        .animation(Theme.motion, value: model.message)
        .task(id: model.message) {
            guard model.message != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { model.message = nil }
        }
    }
}
