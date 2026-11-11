import Foundation

/// The starter allowlist every install gets once: places where apps unblock automatically.
/// Coordinates: Gym and Soccer Field from Apple Maps search, Home from OpenStreetMap (2026-11-10).
enum DefaultPlaces {
    static let places: [Place] = [
        Place(name: "Gym", address: "IMA, 3924 Montlake Blvd NE",
              latitude: 47.6537024, longitude: -122.3011637, radius: 150),
        Place(name: "Soccer Field", address: "Husky Soccer Stadium",
              latitude: 47.6555924, longitude: -122.2982113, radius: 150),
        Place(name: "Home", address: "The M, 4700 Brooklyn Ave NE",
              latitude: 47.6634292, longitude: -122.3138755, radius: 150),
    ]

    /// Starter places with no location yet. They show up as "Set location" rows.
    static let slots: [String] = []
}
