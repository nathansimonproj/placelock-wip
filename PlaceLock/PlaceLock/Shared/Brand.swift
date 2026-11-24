import Foundation
import UIKit

/// The look shared by the app and the block screen. The extensions have no asset catalog,
/// so the accent lives here too. Keep it in step with `AccentColor` in Assets.xcassets.
enum Brand {
    /// Dark sage #3E5F51 in light mode (white text on it passes WCAG AA at about 7:1),
    /// and a soft gray sage #95B0A2 in dark mode, where it's mostly text on the dark gradient.
    static let accent = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x95 / 255, green: 0xB0 / 255, blue: 0xA2 / 255, alpha: 1)
            : UIColor(red: 0x3E / 255, green: 0x5F / 255, blue: 0x51 / 255, alpha: 1)
    }

    /// Picking an app doesn't block its website, and iOS doesn't say which site goes with which
    /// app, so the app picker steps suggest picking it too.
    static let websiteTip = "Also pick each app's website (like youtube.com), so the browser isn't a way around."

    // MARK: About links (Settings tab › About)

    // Hosted on GitHub Pages (repo nathansimonproj/cove) since 2026-11-23; the pages' source is
    // docs/privacy and docs/support. While one is nil, its row is hidden, so nothing made-up
    // ships. Apple requires the privacy policy to be reachable in the app.
    // Each must be an https address; the email is a plain address like name@example.com.
    // "Contact support" opens the email if it's set, otherwise the support page.

    /// The hosted privacy policy, e.g. "https://…/privacy".
    static let privacyPolicyURL: String? = "https://nathansimonproj.github.io/cove/privacy/"
    /// The support page (App Store Connect asks for one too).
    static let supportURL: String? = "https://nathansimonproj.github.io/cove/"
    /// The support email.
    static let supportEmail: String? = "nsimon06@uw.edu"

    /// The block screen's button.
    static let shieldButton = "Back to focus"

    /// "Opens at Library, Gym or Home."
    static func opensAt(_ places: [String]) -> String {
        places.isEmpty ? "Add a place in Cove to open it there." : "Opens at \(list(places))."
    }

    /// The block screen's subtitle, two lines:
    /// "Estimated @ Suzzallo Library · 2 min ago" and "Opens at Library, Gym or Home."
    /// The first line is left out when there's no estimate or it's over a day old.
    static func shieldSubtitle(estimate: SharedStore.Estimate?, places: [String], now: Date = .now) -> String {
        [estimated(estimate, now: now), opensAt(places)].compactMap { $0 }.joined(separator: "\n")
    }

    /// "Estimated @ Suzzallo Library · 2 min ago". Nil when missing or older than a day.
    static func estimated(_ estimate: SharedStore.Estimate?, now: Date = .now) -> String? {
        guard let estimate else { return nil }
        let age = now.timeIntervalSince(estimate.at)
        guard age < 24 * 3600 else { return nil }
        let ago = switch age {
        case ..<60: "just now"
        case ..<3600: "\(Int(age / 60)) min ago"
        default: "\(Int(age / 3600)) h ago"
        }
        return "Estimated @ \(estimate.label) · \(ago)"
    }

    /// "Library", "Library or Gym", "Library, Gym or Home".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return "\(names.dropLast().joined(separator: ", ")) or \(names[names.count - 1])"
        }
    }
}
