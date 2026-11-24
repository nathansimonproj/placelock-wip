import CoreLocation
import Foundation

// Whether you're inside each place, decided from Cove's own location fixes, with iOS's geofence
// events as a fallback. Pure: no Core Location managers, no clocks, no storage. `LocationEngine`
// feeds it readings, and `LockRules.decide` turns the result into lock or unlock.
//
// The rule that shapes everything: whatever unblocks must also be what blocks. Each place's state
// only changes on confident evidence, and an iOS reading older than the last change is ignored, so
// a later pass can never undo a decision on weaker or older evidence.

/// One location fix, reduced to what the rules use. Codable so traces can be recorded and replayed.
struct Fix: Equatable, Codable {
    var latitude: Double
    var longitude: Double
    /// Horizontal accuracy in meters. Negative means the fix is invalid.
    var accuracy: Double
    /// Meters per second. Negative means unknown (Wi-Fi and cell fixes have no speed).
    var speed: Double = -1
    var at: Date

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    init(latitude: Double, longitude: Double, accuracy: Double, speed: Double = -1, at: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.speed = speed
        self.at = at
    }

    init(_ location: CLLocation) {
        self.init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                  accuracy: location.horizontalAccuracy, speed: location.speed, at: location.timestamp)
    }

    func distance(from other: Fix) -> Double { location.distance(from: other.location) }
}

enum PresenceRules {
    // MARK: Thresholds (tuned from shadow-mode traces; see TraceReplayTests)

    /// Older fixes are ignored. Also drops the cached fix Core Location may hand out first.
    static let maxFixAge: TimeInterval = 15
    /// One fix unblocks when its whole accuracy circle is inside, give or take this much.
    static let insideSlack = 25.0
    /// Two fixes at least `pairInsideGap` apart, centers inside, each at least this accurate.
    static let pairInsideAccuracy = 65.0
    static let pairInsideGap: TimeInterval = 5
    /// Blocking needs GPS-grade fixes. Indoor Wi-Fi fixes (±30–65 m, sometimes kilometers off)
    /// can't block on their own.
    static let outsideAccuracy = 30.0
    /// A blocking fix must be this far past the edge, on top of its accuracy.
    static let outsideSlack = 25.0
    static let pairOutsideGap: TimeInterval = 10
    /// A pair's first fix stops counting after this.
    static let pairWindow: TimeInterval = 120
    /// Faster than this from the last inside fix is a bad fix, not a trip.
    static let maxSpeed = 50.0
    /// An iOS event is ignored when a fix this recent says otherwise.
    static let geofenceLookback: TimeInterval = 60

    /// What's known about one place.
    struct PlaceState: Codable, Equatable {
        var presence: Presence = .unknown
        /// When `presence` last changed. iOS readings from before this are ignored.
        var since: Date?
        /// The latest fix that put you inside (for the speed check).
        var lastInsideFix: Fix?
        /// The first fix of a pair still waiting for its second.
        var candidateInside: Fix?
        var candidateOutside: Fix?
        /// The latest valid fix of any kind (for checking iOS events against).
        var lastFix: Fix?
        /// Why `presence` last changed, for logs and traces.
        var reason: Reason?
    }

    enum Reason: String, Codable, Equatable {
        case accurateFixInside, twoFixesInside, twoFixesOutside, geofenceInside, geofenceOutside
    }

    enum Reading: Equatable {
        case fix(Fix)
        /// An iOS geofence event for one place (or the state it reports at launch), with the
        /// event's own date.
        case geofence(UUID, Presence, at: Date)
    }

    // MARK: Stepping

    /// Applies one reading to every place.
    static func step(_ states: [UUID: PlaceState], places: [Place], reading: Reading, now: Date) -> [UUID: PlaceState] {
        var next: [UUID: PlaceState] = [:]
        for place in places {
            next[place.id] = step(states[place.id] ?? PlaceState(), place: place, reading: reading, now: now)
        }
        return next
    }

    /// The per-place result, as `LockRules` takes it.
    static func presence(_ states: [UUID: PlaceState]) -> [UUID: Presence] {
        states.mapValues(\.presence)
    }

    static func step(_ state: PlaceState, place: Place, reading: Reading, now: Date) -> PlaceState {
        switch reading {
        case .fix(let fix): stepFix(state, place: place, fix: fix, now: now)
        case .geofence(let id, let presence, let at):
            id == place.id ? stepGeofence(state, place: place, presence: presence, at: at) : state
        }
    }

    /// A fix counts if it's valid and fresh (not cached, not from the future).
    static func usable(_ fix: Fix, now: Date) -> Bool {
        fix.accuracy >= 0 && now.timeIntervalSince(fix.at) <= maxFixAge && fix.at.timeIntervalSince(now) <= 5
    }

    /// One fix that's enough to unblock: its center is inside, its accuracy circle is inside too
    /// (give or take the slack), and it's accurate for the place's size. The slack never lets a
    /// fix whose center is outside count: that would make the place bigger than you drew it.
    static func confidentlyInside(_ fix: Fix, place: Place) -> Bool {
        let d = place.distanceOutside(fix.location)
        return d <= 0 && d + fix.accuracy <= insideSlack && fix.accuracy <= max(30, place.radius * 0.6)
    }

    /// A fix that leans inside: center inside, reasonably accurate. Two of these unblock.
    static func supportsInside(_ fix: Fix, place: Place) -> Bool {
        place.distanceOutside(fix.location) <= 0 && fix.accuracy <= pairInsideAccuracy
    }

    /// A GPS-grade fix clearly past the edge. Two of these block.
    static func confidentlyOutside(_ fix: Fix, place: Place) -> Bool {
        fix.accuracy <= outsideAccuracy && place.distanceOutside(fix.location) > fix.accuracy + outsideSlack
    }

    /// A fix that leans outside: its center is past the edge by more than its accuracy.
    static func supportsOutside(_ fix: Fix, place: Place) -> Bool {
        place.distanceOutside(fix.location) > fix.accuracy
    }

    /// False when getting from the last inside fix to `fix` would take an impossible speed.
    static func plausible(_ fix: Fix, after last: Fix?) -> Bool {
        guard let last else { return true }
        let seconds = fix.at.timeIntervalSince(last.at)
        guard seconds > 0 else { return false }
        guard seconds < 600 else { return true } // long gaps: anything's possible
        return fix.distance(from: last) / seconds <= maxSpeed
    }

    private static func stepFix(_ state: PlaceState, place: Place, fix: Fix, now: Date) -> PlaceState {
        guard usable(fix, now: now) else { return state }
        var s = state
        s.lastFix = fix
        if let c = s.candidateInside, fix.at.timeIntervalSince(c.at) > pairWindow { s.candidateInside = nil }
        if let c = s.candidateOutside, fix.at.timeIntervalSince(c.at) > pairWindow { s.candidateOutside = nil }

        let leansIn = supportsInside(fix, place: place)
        if leansIn { s.candidateOutside = nil } // a good inside fix breaks an outside pair

        if s.presence == .inside {
            if leansIn {
                s.lastInsideFix = fix
                return s
            }
            guard confidentlyOutside(fix, place: place) else { return s } // in between: keep any pair
            guard plausible(fix, after: s.lastInsideFix), plausible(fix, after: s.candidateOutside) else {
                s.candidateOutside = nil // an impossible jump is a bad fix
                return s
            }
            guard let first = s.candidateOutside else {
                s.candidateOutside = fix
                return s
            }
            guard fix.at.timeIntervalSince(first.at) >= pairOutsideGap else { return s }
            return changed(s, to: .outside, reason: .twoFixesOutside, at: fix.at)
        }

        // Unknown or outside: only confident inside evidence moves it to inside.
        if confidentlyInside(fix, place: place) {
            var n = changed(s, to: .inside, reason: .accurateFixInside, at: fix.at)
            n.lastInsideFix = fix
            return n
        }
        if leansIn {
            if let first = s.candidateInside, fix.at.timeIntervalSince(first.at) >= pairInsideGap {
                var n = changed(s, to: .inside, reason: .twoFixesInside, at: fix.at)
                n.lastInsideFix = fix
                return n
            }
            if s.candidateInside == nil { s.candidateInside = fix }
            return s
        }
        s.candidateInside = nil
        // From unknown, two GPS-grade fixes outside settle it as outside.
        if s.presence == .unknown, confidentlyOutside(fix, place: place) {
            guard let first = s.candidateOutside else {
                s.candidateOutside = fix
                return s
            }
            if fix.at.timeIntervalSince(first.at) >= pairOutsideGap {
                return changed(s, to: .outside, reason: .twoFixesOutside, at: fix.at)
            }
        }
        return s
    }

    /// iOS's reading is the fallback: it applies unless it's older than the last change, or a fix
    /// from within a minute of it says otherwise.
    private static func stepGeofence(_ state: PlaceState, place: Place, presence: Presence, at: Date) -> PlaceState {
        guard presence != .unknown, presence != state.presence else { return state }
        if let since = state.since, at <= since { return state }
        if let fix = state.lastFix, abs(at.timeIntervalSince(fix.at)) <= geofenceLookback {
            let disagrees = presence == .inside ? supportsOutside(fix, place: place) : supportsInside(fix, place: place)
            if disagrees { return state }
        }
        return changed(state, to: presence, reason: presence == .inside ? .geofenceInside : .geofenceOutside, at: at)
    }

    private static func changed(_ state: PlaceState, to presence: Presence, reason: Reason, at: Date) -> PlaceState {
        var s = state
        s.presence = presence
        s.since = at
        s.reason = reason
        s.candidateInside = nil
        s.candidateOutside = nil
        if presence != .inside { s.lastInsideFix = nil }
        return s
    }
}
