import UIKit

/// The look shared by the app and the block screen. The extensions have no asset catalog,
/// so the accent lives here too. Keep it in step with `AccentColor` in Assets.xcassets.
enum Brand {
    /// Muted sage: #4F7A68 in light mode, #7FB09A in dark.
    static let accent = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x7F / 255, green: 0xB0 / 255, blue: 0x9A / 255, alpha: 1)
            : UIColor(red: 0x4F / 255, green: 0x7A / 255, blue: 0x68 / 255, alpha: 1)
    }

    /// The block screen's button.
    static let shieldButton = "Back to focus"

    /// The block screen's subtitle: "Opens at Library, Gym or Home."
    static func opensAt(_ places: [String]) -> String {
        places.isEmpty ? "Add a place in PlaceLock to open it there." : "Opens at \(list(places))."
    }

    /// "Library", "Library or Gym", "Library, Gym or Home".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return "\(names.dropLast().joined(separator: ", ")) or \(names.last!)"
        }
    }
}
