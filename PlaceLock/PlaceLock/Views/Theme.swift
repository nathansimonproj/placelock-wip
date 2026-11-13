import SwiftUI

/// The few values every screen shares. The restraint is the style: system fonts, SF Symbols,
/// one accent (`AccentColor`), and orange only for a 24 h wait.
enum Theme {
    /// Spacing: 8 / 16 / 32, nothing in between.
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 32

    /// Cards and sheets. Chips are capsules.
    static let radius: CGFloat = 16

    /// "Locked" / "Unlocked" on Home.
    static let statusFont = Font.system(size: 44, weight: .semibold, design: .rounded)

    /// The one animation: lock ↔ unlock.
    static let motion = Animation.smooth(duration: 0.4)

    /// Only for countdowns ("Starts in 18 h", "Unblocks in 3 h").
    static let waiting = Color.orange

    /// Deep evening while locked, light and airy while unlocked.
    static func gradient(unlocked: Bool) -> LinearGradient {
        LinearGradient(
            colors: unlocked
                ? [Color(red: 0.93, green: 0.96, blue: 0.94), Color(red: 0.80, green: 0.89, blue: 0.84)]
                : [Color(red: 0.09, green: 0.13, blue: 0.12), Color(red: 0.18, green: 0.29, blue: 0.25)],
            startPoint: .top, endPoint: .bottom)
    }

    /// Glass behind list rows on the gradient.
    static var rowBackground: some View { Rectangle().fill(.ultraThinMaterial) }
}

/// The Home look for any screen: the lock-state gradient behind it, dark text styles while
/// locked, and a tab bar and navigation bar that match.
private struct CalmBackground: ViewModifier {
    @EnvironmentObject private var model: AppModel

    func body(content: Content) -> some View {
        let unlocked = model.activePlace != nil
        content
            .background(Theme.gradient(unlocked: unlocked).ignoresSafeArea())
            .environment(\.colorScheme, unlocked ? .light : .dark)
            // Lists resolve the accent from the window (light), so pick the variant by hand:
            // the darker sage is hard to read on the locked gradient.
            .tint(Color(uiColor: Brand.accent.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: unlocked ? .light : .dark))))
            .toolbarColorScheme(unlocked ? .light : .dark, for: .tabBar, .navigationBar)
            .animation(.smooth(duration: 1.2), value: unlocked)
    }
}

extension View {
    func calmBackground() -> some View { modifier(CalmBackground()) }

    /// For a `List` on the gradient: no gray backdrop. Give its sections `.calmRows()`.
    func calmList() -> some View {
        scrollContentBackground(.hidden).calmBackground()
    }

    /// Glass rows. Put it on each `Section` (a row-background on the `List` itself is ignored).
    func calmRows() -> some View { listRowBackground(Theme.rowBackground) }
}
