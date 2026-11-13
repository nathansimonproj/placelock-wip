import FamilyControls
import SwiftUI

/// Variant C, "Calm": Home as a quiet room. Locked is a deep evening gradient with a slowly
/// breathing circle (a nod to one sec's breathing pause); unlocked turns light and airy.
/// No streaks or scores: reviewers say those turn focus apps into one more thing to check.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: LocationService
    @Binding var placeSheet: PlaceSheet?
    var showRules: () -> Void

    private var unlocked: Bool { model.activePlace != nil }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 0) {
                if needsFix { FixBanner().padding(.horizontal, Theme.medium).padding(.top, Theme.small) }
                Spacer(minLength: Theme.medium)
                BreathingLock(unlocked: unlocked)
                status(now: context.date)
                    .padding(.top, Theme.large)
                Spacer(minLength: Theme.medium)
                resting
                    .padding(.bottom, 20)
                places
                    .padding(.bottom, Theme.medium)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background.ignoresSafeArea())
        // Locked is dark whatever the system setting, so text and glass read on the gradient.
        .environment(\.colorScheme, unlocked ? .light : .dark)
        .toolbarColorScheme(unlocked ? .light : .dark, for: .tabBar)
        .overlay(alignment: .bottom) { Toast().padding(.bottom, 150) }
        .animation(.smooth(duration: 1.2), value: unlocked)
    }

    private var needsFix: Bool { !location.hasAlways || model.screenTimeAccess != .approved }

    private var background: some View {
        LinearGradient(
            colors: unlocked
                ? [Color(red: 0.93, green: 0.96, blue: 0.94), Color(red: 0.80, green: 0.89, blue: 0.84)]
                : [Color(red: 0.09, green: 0.13, blue: 0.12), Color(red: 0.18, green: 0.29, blue: 0.25)],
            startPoint: .top, endPoint: .bottom)
    }

    // MARK: Status

    private func status(now: Date) -> some View {
        let working = model.places.filter { $0.isActive() }.map(\.name)
        return VStack(spacing: 10) {
            Text(unlocked ? "Unlocked" : "Locked")
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .contentTransition(.opacity)
            Group {
                if let place = model.activePlace, let session = model.session {
                    Text("at \(place.name) for \(now.timeIntervalSince(session.visitStartedAt).hoursMinutes)")
                } else if let since = model.lockedSince {
                    Text("for \(now.timeIntervalSince(since).hoursMinutes)")
                }
            }
            .font(.title3.monospacedDigit())
            .foregroundStyle(.secondary)

            Group {
                if unlocked {
                    Button { model.lockUntilLeave() } label: {
                        Label("Lock until I leave", systemImage: "lock.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if model.blockList.isEmpty {
                    Button("Choose apps to block", action: showRules).fontWeight(.semibold)
                } else if model.places.isEmpty {
                    Button("Add a place") { placeSheet = .add }.fontWeight(.semibold)
                } else if !working.isEmpty {
                    Text("Breathe. Your apps open at \(Brand.list(working)).")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .padding(.top, Theme.small)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.large)
    }

    // MARK: Resting apps

    /// The blocked apps, dimmed: "resting" rather than "blocked".
    @ViewBuilder
    private var resting: some View {
        if !model.blockList.isEmpty {
            VStack(spacing: 10) {
                HStack(spacing: -6) {
                    ForEach(model.blockList.simulatedApps.prefix(6), id: \.self) { name in
                        AppBubble { Image(systemName: SimulatedApps.symbol(for: name)) }
                    }
                    ForEach(Array(model.blockList.selection.applicationTokens.prefix(6)), id: \.self) { token in
                        AppBubble { Label(token).labelStyle(.iconOnly) }
                    }
                }
                Text(unlocked ? "\(model.blockedCount) apps open here" : "\(model.blockedCount) apps resting")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .opacity(unlocked ? 1 : 0.7)
        }
    }

    // MARK: Places

    private var places: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.places) { place in
                    let isHere = place.id == model.activePlace?.id
                    Button { placeSheet = .edit(place) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: place.symbol)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(isHere ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).font(.subheadline.weight(.semibold))
                                Group {
                                    if !place.isActive(), let starts = place.activeAfter {
                                        Text("Starts in \(starts.shortTimeLeft)").foregroundStyle(Theme.waiting)
                                    } else if isHere {
                                        Text("You're here")
                                    } else {
                                        Text("Opens here").foregroundStyle(.secondary)
                                    }
                                }
                                .font(.caption)
                            }
                        }
                        .foregroundStyle(isHere ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .frame(width: 112, alignment: .leading)
                        .padding(14)
                        .background {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(isHere ? AnyShapeStyle(Color(uiColor: Brand.accent)) : AnyShapeStyle(.ultraThinMaterial))
                        }
                    }
                    .buttonStyle(.plain)
                }
                ForEach(model.placeSlots, id: \.self) { slot in
                    Button { placeSheet = .fill(slot: slot) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: Place.symbol(for: slot)).font(.system(size: 18, weight: .medium))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(slot).font(.subheadline.weight(.semibold))
                                Text("Set location").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 112, alignment: .leading)
                        .padding(14)
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .buttonStyle(.plain)
                }
                Button { placeSheet = .add } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.medium))
                        .frame(width: 56)
                        .frame(maxHeight: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .disabled(model.places.count >= GeofenceMonitor.maxPlaces)
                .accessibilityLabel("Add place")
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.medium)
        }
    }
}

// MARK: - Pieces

/// The lock inside two soft rings that grow and shrink over 8 s: breathe in, breathe out.
private struct BreathingLock: View {
    let unlocked: Bool
    @State private var inhale = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(unlocked ? 0.35 : 0.05))
                .frame(width: 250, height: 250)
                .scaleEffect(inhale ? 1 : 0.82)
            Circle()
                .fill(.white.opacity(unlocked ? 0.5 : 0.08))
                .frame(width: 180, height: 180)
                .scaleEffect(inhale ? 1 : 0.88)
            Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(unlocked ? AnyShapeStyle(Color(uiColor: Brand.accent)) : AnyShapeStyle(.white))
                .contentTransition(.symbolEffect(.replace))
        }
        .onAppear {
            guard !reduceMotion else { inhale = true; return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { inhale = true }
        }
        .accessibilityHidden(true)
    }
}

private struct AppBubble<Icon: View>: View {
    @ViewBuilder let icon: Icon

    var body: some View {
        icon
            .font(.system(size: 16, weight: .medium))
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.15)))
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
                Text("Fix").fontWeight(.semibold)
            }
            .font(.subheadline)
            .padding(.horizontal, Theme.medium)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.radius))
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
