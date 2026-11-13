import CoreLocation
import SwiftUI

/// First-run setup, shown once on a new install. Each permission is asked on the step that
/// explains it. Every step can be skipped: Home's fix banner catches whatever is left.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: LocationService

    enum Step: String, CaseIterable {
        case location, screenTime, apps, places, notifications
    }

    /// The Screen Time step only exists with real blocking (paid team).
    private var steps: [Step] {
        Step.allCases.filter { $0 != .screenTime || !ShieldManager.isSimulated }
    }

    // Debug builds: launch with `-onboardingStep places` to open on a step (for screenshots).
    @State private var step: Step = {
        #if DEBUG
        Step(rawValue: UserDefaults.standard.string(forKey: "onboardingStep") ?? "") ?? .location
        #else
        .location
        #endif
    }()
    @State private var showPicker = false
    @State private var placeSheet: PlaceSheet?
    @State private var screenTimeError: String?

    private var index: Int { steps.firstIndex(of: step) ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
                    .combined(with: .opacity))
        }
        .animation(.default, value: step)
        .background(Color(.systemGroupedBackground))
        .blockedAppPicker(isPresented: $showPicker, model: model)
        .sheet(item: $placeSheet) { sheet in
            Group {
                switch sheet {
                case .add: AddPlaceView()
                case .fill(let slot): AddPlaceView(slot: slot)
                case .edit(let place): AddPlaceView(editing: place)
                }
            }
            .environmentObject(model)
            .environmentObject(location)
        }
    }

    private var header: some View {
        HStack {
            Button("Back", systemImage: "chevron.left") { step = steps[index - 1] }
                .labelStyle(.iconOnly)
                .opacity(index > 0 ? 1 : 0)
                .disabled(index == 0)
            Spacer()
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule()
                        .fill(i <= index ? Color.accentColor : Color(.tertiarySystemFill))
                        .frame(width: i == index ? 20 : 8, height: 8)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(index + 1) of \(steps.count)")
            Spacer()
            Image(systemName: "chevron.left").opacity(0) // balances the back button
        }
        .font(.title3.weight(.semibold))
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .location: locationStep
        case .screenTime: screenTimeStep
        case .apps: appsStep
        case .places: placesStep
        case .notifications: notificationsStep
        }
    }

    private func next() {
        if index + 1 < steps.count { step = steps[index + 1] } else { model.finishOnboarding() }
    }

    // MARK: Steps

    private var locationStep: some View {
        StepPage(symbol: "location.fill",
                 title: "Apps unblock where you choose",
                 text: "PlaceLock keeps distracting apps blocked everywhere except the places you pick, like the gym or home.\n\nTo notice when you arrive and leave, even with the app closed, it needs your location set to **Always**. Your location stays on this phone.") {
            if location.hasAlways {
                Done("Location is set to Always")
            } else if location.authorization == .authorizedWhenInUse {
                Text("Location is set to While Using. Choose **Always** in Settings › PlaceLock › Location.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        } actions: {
            if location.hasAlways {
                PrimaryButton("Continue", action: next)
            } else if location.authorization == .notDetermined {
                PrimaryButton("Allow location") { location.requestPermission() }
                SkipButton(action: next)
            } else {
                PrimaryButton("Open Settings") {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                }
                SkipButton(action: next)
            }
        }
    }

    private var screenTimeStep: some View {
        StepPage(symbol: "hourglass",
                 title: "Allow Screen Time access",
                 text: "PlaceLock blocks apps through Screen Time, the same way iOS's own limits work. Apple asks you to confirm with Face ID or your passcode.") {
            if model.screenTimeAccess == .approved {
                Done("Screen Time access is on")
            } else if let screenTimeError {
                Text(screenTimeError).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
        } actions: {
            if model.screenTimeAccess == .approved {
                PrimaryButton("Continue", action: next)
            } else {
                PrimaryButton("Allow Screen Time access") {
                    Task {
                        do {
                            try await ShieldManager.requestAuthorization()
                            screenTimeError = nil
                        } catch {
                            screenTimeError = "That didn't work: \(error.localizedDescription)"
                        }
                        await model.reconcile() // re-reads access and puts the block on
                    }
                }
                SkipButton(action: next)
            }
        }
    }

    private var appsStep: some View {
        StepPage(symbol: "apps.iphone",
                 title: "Pick apps to block",
                 text: "Choose the apps that pull you in. They stay blocked until you're at one of your places.\n\nFor your first 24 hours you can change this freely. After that, removing an app takes 24 hours, so you can't unblock one on a whim.") {
            if !model.blockList.isEmpty {
                Done("Blocking \(model.blockList.summary)")
            }
        } actions: {
            if model.blockList.isEmpty {
                PrimaryButton("Choose apps") { showPicker = true }
                    .disabled(model.screenTimeAccess != .approved)
                SkipButton(action: next)
            } else {
                PrimaryButton("Continue", action: next)
                Button("Change apps") { showPicker = true }.padding(.top, 4)
            }
        }
    }

    private var placesStep: some View {
        StepPage(symbol: "mappin.and.ellipse",
                 title: "Where should apps unblock?",
                 text: model.places.isEmpty && model.placeSlots.isEmpty
                    ? "Add the places where you're allowed to use your apps, like the gym or home. Apps unblock on their own while you're there, and lock again when you leave."
                    : "Apps unblock on their own while you're at one of these, and lock again when you leave.") {
            VStack(spacing: 8) {
                ForEach(model.places) { place in
                    PlaceLine(symbol: place.symbol, name: place.name,
                              detail: place.address ?? "\(Int(place.radius)) m", isPlace: true) {
                        placeSheet = .edit(place)
                    }
                }
                ForEach(model.placeSlots, id: \.self) { slot in
                    PlaceLine(symbol: Place.symbol(for: slot), name: slot, detail: "Set location", isPlace: false) {
                        placeSheet = .fill(slot: slot)
                    }
                }
                if !model.places.isEmpty {
                    Button("Add another place", systemImage: "plus.circle.fill") { placeSheet = .add }
                        .disabled(model.places.count >= GeofenceMonitor.maxPlaces)
                        .padding(.top, 4)
                }
                Text("Places you add in your first 24 hours work right away. After that, new places take 24 hours to start working.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        } actions: {
            if model.places.isEmpty {
                PrimaryButton("Add a place") { placeSheet = .add }
                SkipButton(title: "Skip for now", action: next)
            } else {
                PrimaryButton("Continue", action: next)
            }
        }
    }

    private var notificationsStep: some View {
        StepPage(symbol: "bell.badge.fill",
                 title: "Know when apps lock",
                 text: "Get a heads-up when you arrive and apps unblock, when you leave and they lock again, and when a new place starts working.") {
            EmptyView()
        } actions: {
            PrimaryButton("Turn on notifications") {
                Task {
                    await model.requestNotificationPermission()
                    next()
                }
            }
            SkipButton(title: "Not now", action: next)
        }
    }
}

// MARK: - Pieces

/// One step: a big symbol, a title, an explanation, step-specific content, and buttons at the bottom.
private struct StepPage<Extra: View, Actions: View>: View {
    let symbol: String
    let title: String
    let text: LocalizedStringKey
    @ViewBuilder let extra: Extra
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    // Every step in the one accent, so the flow reads as one calm sequence.
                    Image(systemName: symbol)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 96, height: 96)
                        .background(Circle().fill(.tint.opacity(0.12)))
                        .padding(.top, 24)
                    Text(title).font(.title.bold()).multilineTextAlignment(.center)
                    Text(text).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    extra
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
            VStack(spacing: 8) { actions }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .padding(.top, 8)
        }
    }
}

private struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

private struct SkipButton: View {
    var title = "Skip"
    let action: () -> Void

    var body: some View {
        Button(title, action: action).padding(.top, 4)
    }
}

/// A "done" line under a step's text.
private struct Done: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.tint)
            .multilineTextAlignment(.center)
    }
}

private struct PlaceLine: View {
    let symbol: String
    let name: String
    let detail: String
    /// A saved place (accent symbol) or a slot still waiting for a location (gray).
    let isPlace: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isPlace ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
    }
}
