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
}
