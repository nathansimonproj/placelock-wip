import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The screen iOS shows over a blocked app: "Instagram is blocked · Unblocks at Gym, Soccer Field or Home".
/// iOS asks for this whenever a blocked app or website is opened. It reads the place names the app
/// shares in the App Group (`SharedStore.allowedPlaceNames`).
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        shield(for: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        shield(for: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        shield(for: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        shield(for: webDomain.domain)
    }

    private func shield(for name: String?) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            icon: UIImage(systemName: "lock.fill"),
            title: .init(text: "\(name ?? "This app") is blocked", color: .label),
            subtitle: .init(text: Self.unblocksAt(SharedStore.allowedPlaceNames), color: .secondaryLabel),
            primaryButtonLabel: .init(text: "OK", color: .white),
            primaryButtonBackgroundColor: .systemBlue)
    }

    /// "Unblocks at Gym, Soccer Field or Home."
    static func unblocksAt(_ places: [String]) -> String {
        switch places.count {
        case 0: return "Add a place in PlaceLock to unblock it there."
        case 1: return "Unblocks at \(places[0])."
        default: return "Unblocks at \(places.dropLast().joined(separator: ", ")) or \(places.last!)."
        }
    }
}
