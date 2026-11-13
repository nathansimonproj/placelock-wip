import FamilyControls
import SwiftUI

/// Variant A, "Today": a calm dashboard. Status up top, three numbers, an hour-by-hour strip of
/// the day (inspired by Opal's home), then your places with what each did for you today.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: LocationService
    @Binding var placeSheet: PlaceSheet?
    var showRules: () -> Void

    var body: some View {
        NavigationStack {
            // Redraw every minute so durations and the strip stay current.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.medium) {
                        Text(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .padding(.top, -Theme.small)
                        if needsFix { FixBanner() }
                        statusCard(now: context.date)
                        stats
                        dayStrip(now: context.date)
                        placesSection(now: context.date)
                    }
                    .padding(.horizontal, Theme.medium)
                    .padding(.bottom, Theme.large)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .overlay(alignment: .bottom) { Toast() }
            .animation(Theme.motion, value: model.activePlace?.id)
        }
    }

    private var needsFix: Bool { !location.hasAlways || model.screenTimeAccess != .approved }

    // MARK: Status

    private func statusCard(now: Date) -> some View {
        let place = model.activePlace
        let unlocked = place != nil
        return VStack(alignment: .leading, spacing: Theme.medium) {
            HStack(spacing: Theme.medium) {
                Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(unlocked ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(unlocked ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(.tint.opacity(0.12))))
                VStack(alignment: .leading, spacing: 2) {
                    Text(unlocked ? "Unlocked" : "Locked")
                        .font(.system(.title, design: .rounded, weight: .semibold))
                    Text(statusLine(now: now))
                        .font(.subheadline)
                        .foregroundStyle(unlocked ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                }
                Spacer(minLength: 0)
            }
            if unlocked {
                Button { model.lockUntilLeave() } label: {
                    Label("Lock until I leave", systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.2), in: Capsule())
                }
                .buttonStyle(.plain)
            } else if model.blockList.isEmpty {
                Button("Choose apps to block", systemImage: "plus", action: showRules)
                    .font(.subheadline.weight(.semibold))
            } else if model.places.isEmpty {
                Button("Add a place", systemImage: "plus") { placeSheet = .add }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(unlocked ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(unlocked ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
        )
    }

    private func statusLine(now: Date) -> String {
        if let place = model.activePlace, let session = model.session {
            return "at \(place.name) · \(now.timeIntervalSince(session.visitStartedAt).hoursMinutes)"
        }
        let working = model.places.filter { $0.isActive() }.map(\.name)
        if let since = model.lockedSince {
            return "for \(now.timeIntervalSince(since).hoursMinutes) · opens at \(Brand.list(working))"
        }
        return working.isEmpty ? "No places working yet" : "Opens at \(Brand.list(working))"
    }

    // MARK: Numbers

    private var stats: some View {
        HStack(spacing: Theme.small + 4) {
            StatTile(value: "\(Int((model.lockedShareToday * 100).rounded()))%", label: "Locked today", symbol: "lock")
            StatTile(value: "\(model.unlocksToday)", label: model.unlocksToday == 1 ? "Unlock" : "Unlocks", symbol: "lock.open")
            StatTile(value: "\(model.blockedCount)", label: "Blocked", symbol: "app.badge")
        }
    }

    // MARK: Day strip

    /// 24 bars, one per hour: accent = locked minutes, gray = unlocked. Future hours are a faint dot.
    private func dayStrip(now: Date) -> some View {
        let start = Calendar.current.startOfDay(for: now)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your day").font(.headline)
                Spacer()
                LegendDot(color: .accentColor, text: "Locked")
                LegendDot(color: Color(.systemGray4), text: "Unlocked")
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { hour in
                    let from = start.addingTimeInterval(Double(hour) * 3600)
                    let to = min(from.addingTimeInterval(3600), now)
                    if to <= from {
                        Capsule().fill(Color(.quaternarySystemFill)).frame(height: 4)
                    } else {
                        let span = to.timeIntervalSince(from)
                        let unlockedShare = min(1, model.unlockedTime(from: from, to: to) / span)
                        let fill = span / 3600 // a partly-elapsed hour is a shorter bar
                        VStack(spacing: 1) {
                            Color(.systemGray4).frame(height: 64 * fill * unlockedShare)
                            Color.accentColor.frame(height: 64 * fill * (1 - unlockedShare))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                }
            }
            .frame(height: 64, alignment: .bottom)
            HStack {
                ForEach(["12 AM", "6 AM", "12 PM", "6 PM"], id: \.self) { label in
                    Text(label).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(Theme.medium)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.radius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Locked \(Int(model.lockedShareToday * 100)) percent of today")
    }

    // MARK: Places

    private func placesSection(now: Date) -> some View {
        let today = Calendar.current.startOfDay(for: now)
        return VStack(alignment: .leading, spacing: Theme.small) {
            HStack {
                Text("Places").font(.headline)
                Spacer()
                Button("Add", systemImage: "plus") { placeSheet = .add }
                    .font(.subheadline.weight(.medium))
                    .disabled(model.places.count >= GeofenceMonitor.maxPlaces)
            }
            .padding(.top, Theme.small)

            VStack(spacing: 0) {
                ForEach(model.places) { place in
                    let here = place.id == model.activePlace?.id
                    let spent = model.allVisits(now: now)
                        .filter { $0.placeID == place.id }
                        .reduce(0) { $0 + max(0, $1.end.timeIntervalSince(max($1.start, today))) }
                    Button { placeSheet = .edit(place) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: place.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(here ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(here ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.12))))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).foregroundStyle(.primary)
                                Text(place.address ?? "\(Int(place.radius)) m")
                                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if !place.isActive(), let starts = place.activeAfter {
                                Label("Starts in \(starts.shortTimeLeft)", systemImage: "clock")
                                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.waiting)
                            } else if here {
                                Text("Here now").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                            } else if spent >= 60 {
                                Text("\(spent.hoursMinutes) today").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, Theme.medium)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if place.id != model.places.last?.id { Divider().padding(.leading, 62) }
                }
                ForEach(model.placeSlots, id: \.self) { slot in
                    Button { placeSheet = .fill(slot: slot) } label: {
                        Label("\(slot) · Set location", systemImage: Place.symbol(for: slot))
                            .foregroundStyle(.secondary)
                            .padding(Theme.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                if model.places.isEmpty && model.placeSlots.isEmpty {
                    Text("Add the places where your apps should open, like the library or the gym.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(Theme.medium)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.radius))
        }
    }
}

// MARK: - Pieces

private struct StatTile: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.footnote.weight(.semibold)).foregroundStyle(.tint)
            Text(value).font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
                .contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.radius))
    }
}

private struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
        .font(.caption2).foregroundStyle(.secondary)
    }
}

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
                    .padding(.bottom, Theme.medium)
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
