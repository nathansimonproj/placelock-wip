import Foundation

/// The starter allowlist a new install gets once. Empty: people add their own places during
/// first-run setup. To ship starters again, list them here. `places` are ready to use;
/// `slots` are names with no location yet, shown as "Set location" rows.
enum DefaultPlaces {
    static let places: [Place] = []
    static let slots: [String] = []
}
