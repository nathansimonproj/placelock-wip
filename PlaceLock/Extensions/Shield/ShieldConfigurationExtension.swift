import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The screen iOS shows over a blocked app: "Instagram is locked · Opens at Gym, Soccer Field or Home".
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

    /// Calm, not scolding: the moment you hit a block is the moment the app is for.
    private func shield(for name: String?) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            icon: UIImage(systemName: "lock.fill")?.withTintColor(Brand.accent, renderingMode: .alwaysOriginal),
            title: .init(text: "\(name ?? "This app") is locked", color: .label),
            subtitle: .init(text: Brand.opensAt(SharedStore.allowedPlaceNames), color: .secondaryLabel),
            primaryButtonLabel: .init(text: Brand.shieldButton, color: .white),
            primaryButtonBackgroundColor: Brand.accent)
    }
}
