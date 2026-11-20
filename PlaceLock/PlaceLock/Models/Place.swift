import CoreLocation
import Foundation

/// A place where blocked apps may be unlocked.
struct Place: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    /// Short address from search, for display. Nil for places saved by dropping a pin.
    var address: String?
    var latitude: Double
    var longitude: Double
    /// Meters, 50–500. Below 100 m iOS's coarse background fixes can miss you arriving,
    /// so Add place warns below that.
    var radius: Double
    /// A new place only unblocks apps from this time on (24 h after it was added).
    /// Nil means active. Places added during the setup window are active right away.
    var activeAfter: Date? = nil
    /// A move or enlargement waiting out its 24 h. The current circle keeps working until then.
    var pendingChange: PendingChange? = nil

    struct PendingChange: Codable, Hashable {
        var latitude: Double
        var longitude: Double
        var radius: Double
        var appliesAt: Date
    }

    /// True once the place may unblock apps.
    func isActive(at date: Date = .now) -> Bool {
        activeAfter.map { $0 <= date } ?? true
    }

    /// True if a circle at `center` with `radius` fits entirely inside this place's circle,
    /// so switching to it can only make the place stricter.
    func contains(center: CLLocationCoordinate2D, radius newRadius: Double) -> Bool {
        let offset = CLLocation(latitude: center.latitude, longitude: center.longitude).distance(from: location)
        return offset + newRadius <= radius + 1 // 1 m slack for map rounding
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// Icon picked from the name: "Gym" gets a dumbbell, "Home" a house, and so on.
    var symbol: String { Place.symbol(for: name) }

    static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("gym") || n.contains("fitness") || n.contains("ima") { return "dumbbell.fill" }
        if n.contains("home") || n.contains("apartment") || n.contains("dorm") { return "house.fill" }
        if n.contains("soccer") || n.contains("field") { return "soccerball" }
        if n.contains("library") { return "books.vertical.fill" }
        if n.contains("cafe") || n.contains("coffee") { return "cup.and.saucer.fill" }
        return "mappin"
    }

    /// Distance from `location` to the edge of this place (0 or less = inside).
    func distanceOutside(_ location: CLLocation) -> Double {
        location.distance(from: self.location) - radius
    }
}

extension Date {
    /// Compact time left until this date: "23 h", "45 min", "now".
    var shortTimeLeft: String {
        let seconds = timeIntervalSinceNow
        if seconds <= 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        return "\(Int((seconds / 3600).rounded(.up))) h"
    }
}

/// An active unlock: the apps stay unblocked until the user leaves `placeID`.
struct UnlockSession: Codable {
    var placeID: UUID
    /// When this unlock started. (It also restarted on the 8 h recheck, removed 2026-11-19.)
    var startedAt: Date
    /// This visit in the synced history (`sessions.id`).
    var id: UUID
    /// When the visit began.
    var visitStartedAt: Date

    init(placeID: UUID, startedAt: Date, id: UUID = UUID(), visitStartedAt: Date? = nil) {
        self.placeID = placeID
        self.startedAt = startedAt
        self.id = id
        self.visitStartedAt = visitStartedAt ?? startedAt
    }
}

// Hand-written so a session saved before `id` and `visitStartedAt` existed still loads
// (failing to decode would drop an active unlock).
extension UnlockSession {
    private enum CodingKeys: String, CodingKey { case placeID, startedAt, id, visitStartedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let startedAt = try c.decode(Date.self, forKey: .startedAt)
        self.init(placeID: try c.decode(UUID.self, forKey: .placeID), startedAt: startedAt,
                  id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  visitStartedAt: try c.decodeIfPresent(Date.self, forKey: .visitStartedAt))
    }
}
