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

    /// The one background: a deep evening green. It's the same whether apps are locked or not;
    /// only the words and the lock icon change.
    static let gradient = LinearGradient(
        colors: [Color(red: 0.09, green: 0.13, blue: 0.12), Color(red: 0.18, green: 0.29, blue: 0.25)],
        startPoint: .top, endPoint: .bottom)

    /// Glass behind list rows on the gradient.
    static var rowBackground: some View { Rectangle().fill(.ultraThinMaterial) }
}

/// The app's one look for any screen: the dark green gradient behind it, and dark mode for the
/// screen, tab bar and navigation bar whatever the phone's setting.
private struct CalmBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.gradient.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            // Lists resolve the accent from the window (light), so pick the dark variant by hand:
            // the darker sage is hard to read on the gradient.
            .tint(Color(uiColor: Brand.accent.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))))
            // The bars are forced dark too. Left alone on the gradient, iOS's glass tab bar picked
            // dark icons on a dark pill and an almost invisible selected tab.
            .toolbarColorScheme(.dark, for: .tabBar, .navigationBar)
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
