import Foundation

// The shapes of the server's rows (supabase/migrations/*_init.sql). Plain values, no networking.
// Every nullable column is always encoded (as null when empty), so an upsert can clear a field
// and every row in a batch has the same keys, which PostgREST requires.

/// A `places` row.
struct PlaceRecord: Codable, Equatable {
    var id: UUID
    var name: String
    var address: String?
    var kind = "unlock"
    var latitude: Double
    var longitude: Double
    var radiusM: Double
    var activeAfter: Date?
    var pendingLatitude: Double?
    var pendingLongitude: Double?
    var pendingRadiusM: Double?
    var pendingAppliesAt: Date?
    /// Tombstone: the place was deleted.
    var deletedAt: Date?
    /// When this version was made on a phone. Newest wins.
    var updatedAt: Date
    /// Server time of the last applied write. Read only; never uploaded.
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, address, kind, latitude, longitude
        case radiusM = "radius_m", activeAfter = "active_after"
        case pendingLatitude = "pending_latitude", pendingLongitude = "pending_longitude"
        case pendingRadiusM = "pending_radius_m", pendingAppliesAt = "pending_applies_at"
        case deletedAt = "deleted_at", updatedAt = "updated_at", syncedAt = "synced_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(address, forKey: .address)
        try c.encode(kind, forKey: .kind)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(radiusM, forKey: .radiusM)
        try c.encode(activeAfter, forKey: .activeAfter)
        try c.encode(pendingLatitude, forKey: .pendingLatitude)
        try c.encode(pendingLongitude, forKey: .pendingLongitude)
        try c.encode(pendingRadiusM, forKey: .pendingRadiusM)
        try c.encode(pendingAppliesAt, forKey: .pendingAppliesAt)
        try c.encode(deletedAt, forKey: .deletedAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

extension PlaceRecord {
    /// The server's limits (see the table's check constraints).
    static let maxName = 60, maxAddress = 200, radiusRange = 100.0...500.0

    init(_ place: Place, updatedAt: Date, deletedAt: Date? = nil) {
        let name = String(place.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxName))
        self.init(
            id: place.id,
            name: name.isEmpty ? "Place" : name,
            address: place.address.map { String($0.prefix(Self.maxAddress)) },
            latitude: place.latitude,
            longitude: place.longitude,
            radiusM: place.radius.clamped(to: Self.radiusRange),
            activeAfter: place.activeAfter,
            pendingLatitude: place.pendingChange?.latitude,
            pendingLongitude: place.pendingChange?.longitude,
            pendingRadiusM: place.pendingChange?.radius.clamped(to: Self.radiusRange),
            pendingAppliesAt: place.pendingChange?.appliesAt,
            deletedAt: deletedAt,
            updatedAt: updatedAt)
    }

    /// The local place this row describes. Nil for a tombstone.
    var place: Place? {
        guard deletedAt == nil else { return nil }
        var pending: Place.PendingChange?
        if let pendingLatitude, let pendingLongitude, let pendingRadiusM, let pendingAppliesAt {
            pending = .init(latitude: pendingLatitude, longitude: pendingLongitude,
                            radius: pendingRadiusM, appliesAt: pendingAppliesAt)
        }
        return Place(id: id, name: name, address: address, latitude: latitude, longitude: longitude,
                     radius: radiusM, activeAfter: activeAfter, pendingChange: pending)
    }
}

/// Why a session ended. Matches the `sessions.end_reason` check constraint.
enum SessionEnd: String, Codable {
    case left
    case moved
    case lockUntilLeave = "lock_until_leave"
    case placeDeleted = "place_deleted"
    case lostAlways = "lost_always"
    case recheckFailed = "recheck_failed"
    case manual
    case launchCheck = "launch_check"
}

/// A `sessions` row: one visit during which apps were unlocked (or, later, a lock-in).
struct SessionRecord: Codable, Equatable {
    var id: UUID
    var placeID: UUID?
    var kind = "unlock"
    var startedAt: Date
    var endedAt: Date?
    var endReason: SessionEnd?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind
        case placeID = "place_id", startedAt = "started_at", endedAt = "ended_at"
        case endReason = "end_reason", updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(placeID, forKey: .placeID)
        try c.encode(kind, forKey: .kind)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(endReason, forKey: .endReason)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

extension SessionRecord {
    init(_ session: UnlockSession, endedAt: Date? = nil, reason: SessionEnd? = nil, updatedAt: Date) {
        self.init(id: session.id, placeID: session.placeID, startedAt: session.visitStartedAt,
                  endedAt: endedAt.map { max($0, session.visitStartedAt) }, endReason: reason,
                  updatedAt: updatedAt)
    }
}

/// The part of `profiles` the app syncs today.
struct ProfileRecord: Codable {
    var setupEndsAt: Date?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case setupEndsAt = "setup_ends_at", updatedAt = "updated_at"
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { min(max(self, range.lowerBound), range.upperBound) }
}
