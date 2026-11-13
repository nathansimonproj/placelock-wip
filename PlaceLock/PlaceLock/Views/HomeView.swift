import SwiftUI

/// One question, answered at a glance: am I locked? A big calm status in the middle,
/// your places along the bottom, and nothing else unless something needs fixing.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: LocationService
    @Binding var placeSheet: PlaceSheet?
    var showRules: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if needsFix { fixBanner }
            Spacer()
            status
            Spacer()
            places
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { toast }
        .animation(Theme.motion, value: model.activePlace?.id)
        .animation(Theme.motion, value: model.message)
        // A message shows for 3 s, then fades.
        .task(id: model.message) {
            guard model.message != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { model.message = nil }
        }
    }

    // MARK: Status

    private var status: some View {
        let place = model.activePlace
        return VStack(spacing: Theme.medium) {
            Image(systemName: place == nil ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(place == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 140, height: 140)
                .background(Circle().fill(.tint.opacity(place == nil ? 0 : 0.12)))

            VStack(spacing: Theme.small) {
                Text(place == nil ? "Locked" : "Unlocked")
                    .font(Theme.statusFont)
                    .contentTransition(.opacity)
                subtitle
            }

            if model.simulatedSpot != nil {
                Label("Simulated location", systemImage: "location.slash")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if place != nil {
                Button("Lock until I leave", systemImage: "lock.fill") { model.lockUntilLeave() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding(.top, Theme.medium)
            }
        }
        .padding(.horizontal, Theme.large)
        .multilineTextAlignment(.center)
    }

    /// One line under the status. Becomes a link when there's nothing to unlock yet.
    @ViewBuilder
    private var subtitle: some View {
        let working = model.places.filter { $0.isActive() }.map(\.name)
        Group {
            // Links stay in the accent so they read as tappable; plain lines are secondary.
            if let place = model.activePlace {
                Text("at \(place.name)").foregroundStyle(.secondary)
            } else if model.blockList.isEmpty {
                Button("Choose apps to block", action: showRules)
            } else if model.places.isEmpty && model.placeSlots.isEmpty {
                Button("Add a place") { placeSheet = .add }
            } else if working.isEmpty {
                Text("Unlocks once a place starts working").foregroundStyle(.secondary)
            } else {
                Text("Unlocks at \(Brand.list(working))").foregroundStyle(.secondary)
            }
        }
        .font(.title3)
    }

    // MARK: Places

    private var places: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.small) {
                ForEach(model.places) { place in
                    let here = place.id == model.activePlace?.id
                    let waiting = !place.isActive()
                    Button { placeSheet = .edit(place) } label: {
                        Text(waiting ? "\(place.name) · \(place.activeAfter?.shortTimeLeft ?? "")" : place.name)
                            .chip()
                            .foregroundStyle(here ? AnyShapeStyle(.white) : waiting ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                            .background(Capsule().fill(here ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.secondarySystemFill))))
                    }
                    .accessibilityLabel(here ? "\(place.name), here now" : place.name)
                }
                ForEach(model.placeSlots, id: \.self) { slot in
                    Button { placeSheet = .fill(slot: slot) } label: {
                        Text("\(slot) · set").chip()
                            .foregroundStyle(.secondary)
                            .overlay(Capsule().strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .accessibilityLabel("\(slot), set location")
                }
                Button { placeSheet = .add } label: {
                    Image(systemName: "plus").chip()
                        .foregroundStyle(.secondary)
                        .background(Capsule().fill(Color(.secondarySystemFill)))
                }
                .disabled(model.places.count >= GeofenceMonitor.maxPlaces)
                .accessibilityLabel("Add place")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.medium)
        }
        .padding(.bottom, Theme.medium)
    }

    // MARK: Fix banner

    private var needsFix: Bool {
        !location.hasAlways || model.screenTimeAccess != .approved
    }

    /// One thin line when blocking can't work. First-run setup asked already; this catches
    /// a skipped step or access turned off later in Settings.
    private var fixBanner: some View {
        Button(action: fix) {
            HStack(spacing: Theme.small) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.waiting)
                Text(fixText).foregroundStyle(.primary)
                Spacer()
                Text("Fix").fontWeight(.semibold).foregroundStyle(.tint)
            }
            .font(.subheadline)
            .padding(.horizontal, Theme.medium)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.medium)
        .padding(.top, Theme.small)
    }

    private var fixText: String {
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
                await model.reconcile() // re-reads access and puts the block back on
            }
        } else if location.authorization == .notDetermined {
            location.requestPermission()
        } else {
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        }
    }

    // MARK: Toast

    @ViewBuilder
    private var toast: some View {
        if let message = model.message {
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.medium)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.horizontal, Theme.large)
                .padding(.bottom, 72) // above the places row
                .transition(.opacity)
                .onTapGesture { model.message = nil }
        }
    }
}

private extension View {
    /// The capsule shape every place chip shares. Color is set by the caller.
    func chip() -> some View {
        font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Capsule())
    }
}
