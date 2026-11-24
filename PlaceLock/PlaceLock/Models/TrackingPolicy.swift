import CoreLocation
import Foundation

// How hard Cove tracks location, chosen from where you are relative to your places. Pure, so
// `LocationEngine` only applies the result. Balanced battery setting (chosen 2026-11-23):
// track closely only near an edge, or inside a place when there's a sign you're leaving.

enum TrackingPolicy {
    enum Mode: String, Codable, Equatable {
        /// Far from every place: no tracking; iOS's wakes (rings, ~500 m moves, visits) only.
        case dormant
        /// Within ~1 km of a place: coarse tracking to notice the edge coming.
        case approach
        /// Outside, near an edge: best accuracy, so arriving unblocks within seconds.
        case edge
        /// Inside and not leaving: cheap fixes, paused by iOS while the phone sits still.
        case inside
        /// Inside with a sign you might be leaving: best accuracy until you're still or 2 min pass.
        case burst
    }

    /// What Core Location should run for a mode.
    struct Settings: Equatable {
        var running: Bool
        var accuracy: CLLocationAccuracy
        var distanceFilter: CLLocationDistance
    }

    // MARK: Thresholds

    static let approachDistance = 1_000.0
    static let edgeDistance = 150.0
    /// Hysteresis: once in a mode, it takes this much farther to drop out of it.
    static let hysteresis = 50.0
    static let burstLength: TimeInterval = 120
    /// Faster than walking around a room.
    static let movingSpeed = 2.0

    /// Inside a place, a fix this close to the edge (or past it) starts a burst. Scales with the
    /// place, so a small place (all of it near the edge) doesn't keep GPS on: 40 m for 100 m.
    static func edgeBand(radius: Double) -> Double {
        min(max(radius * 0.4, 25), 150)
    }

    struct Input: Equatable {
        /// Distance from the nearest place's edge (negative = inside it), or nil with no places.
        var distanceToEdge: Double?
        /// The nearest place's radius.
        var radius: Double = 100
        /// You're inside some place (waiting places count: Cove must stay running for the wait
        /// to end while you're there).
        var inside: Bool
        /// Core Location says the phone is sitting still (updates paused).
        var stationary: Bool
        /// Updates just resumed after a stationary pause.
        var resumed: Bool = false
        /// The latest fix's speed in m/s, negative if unknown.
        var speed: Double = -1
        /// iOS just reported an exit for the place you're in.
        var exitHint: Bool = false
        /// When the running burst started, if one is running.
        var burstStartedAt: Date?
        var lowPower: Bool
        var previous: Mode
        var now: Date
    }

    /// A sign you might be leaving the place you're in.
    static func leavingSign(_ input: Input) -> Bool {
        if input.resumed || input.exitHint || input.speed > movingSpeed { return true }
        guard let d = input.distanceToEdge else { return false }
        return d > -edgeBand(radius: input.radius)
    }

    static func mode(_ input: Input) -> Mode {
        if input.inside {
            if let started = input.burstStartedAt, !input.stationary,
               input.now.timeIntervalSince(started) < burstLength {
                return .burst
            }
            if !input.stationary, leavingSign(input) { return .burst } // the engine starts a new burst
            return .inside
        }
        guard let d = input.distanceToEdge else { return .dormant }
        let edgeLimit = edgeDistance + (input.previous == .edge || input.previous == .burst ? hysteresis : 0)
        let approachLimit = approachDistance + (input.previous == .approach ? hysteresis : 0)
        if d <= edgeLimit { return input.lowPower ? .approach : .edge }
        if d <= approachLimit { return input.lowPower ? .dormant : .approach }
        return .dormant
    }

    static func settings(for mode: Mode, lowPower: Bool) -> Settings {
        switch mode {
        case .dormant:
            Settings(running: false, accuracy: kCLLocationAccuracyHundredMeters, distanceFilter: kCLDistanceFilterNone)
        case .approach:
            Settings(running: true, accuracy: kCLLocationAccuracyHundredMeters, distanceFilter: 50)
        case .edge:
            Settings(running: true, accuracy: kCLLocationAccuracyBest, distanceFilter: kCLDistanceFilterNone)
        case .inside:
            Settings(running: true, accuracy: kCLLocationAccuracyHundredMeters, distanceFilter: 25)
        case .burst:
            Settings(running: true, accuracy: lowPower ? kCLLocationAccuracyHundredMeters : kCLLocationAccuracyBest,
                     distanceFilter: kCLDistanceFilterNone)
        }
    }
}
