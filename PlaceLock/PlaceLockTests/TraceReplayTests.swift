import CoreLocation
import Foundation
import Testing
@testable import PlaceLock

/// Replays recorded and made-up location traces through `PresenceRules`, the way
/// `LocationEngine` feeds it, and checks the result against what really happened.
///
/// Recorded traces live in PlaceLockTests/Traces/*.jsonl, made with `scripts/trace-fixture.py`
/// (coordinates moved, places renamed, times relative). Each "truth" line says when you really
/// arrived at or left a place. For every fixture:
///   - each arrival unblocks within `arriveWithin`
///   - each departure blocks within `leaveWithin`
///   - nothing blocks while you're really inside, and nothing unblocks while you're really outside
struct TraceReplayTests {
    static let arriveWithin: TimeInterval = 60
    static let leaveWithin: TimeInterval = 120
    /// Truth comes from notes to the minute, so allow this much either side.
    static let slack: TimeInterval = 60

    // MARK: Recorded traces

    static var fixtures: [URL] {
        Bundle(for: Token.self).urls(forResourcesWithExtension: "jsonl", subdirectory: nil) ?? []
    }

    @Test func everyRecordedTraceMeetsItsTruth() throws {
        for url in Self.fixtures {
            let trace = try ReplayTrace(url: url)
            let result = Replay.run(trace)
            for problem in Self.problems(result, truth: trace.truth) {
                Issue.record("\(url.lastPathComponent): \(problem)")
            }
        }
    }

    @Test func theSimulatorFixtureIsBundled() {
        // Guards the test above against silently checking nothing.
        #expect(Self.fixtures.contains { $0.lastPathComponent == "simulator-fast-exit.jsonl" })
    }

    // MARK: Made-up traces

    @Test func aLongStayIndoorsWithWifiNoiseNeverBlocks() {
        for radius in [100.0, 50.0] {
            let trace = Synthetic.stay(radius: radius, seed: 7)
            let result = Replay.run(trace)
            for problem in Self.problems(result, truth: trace.truth) {
                Issue.record("radius \(Int(radius)) m: \(problem)")
            }
        }
    }

    @Test func manySeedsHoldUp() {
        for seed in 1...20 {
            let trace = Synthetic.stay(radius: 100, seed: UInt64(seed))
            let problems = Self.problems(Replay.run(trace), truth: trace.truth)
            #expect(problems.isEmpty, "seed \(seed): \(problems)")
        }
    }

    // MARK: Checking

    struct Truth: Equatable {
        var t: TimeInterval
        var place: String
        var arrive: Bool
    }

    static func problems(_ transitions: [Replay.Transition], truth: [Truth]) -> [String] {
        var problems: [String] = []
        let byPlace = Dictionary(grouping: truth, by: \.place)
        for (place, marks) in byPlace {
            let changes = transitions.filter { $0.place == place }
            let sorted = marks.sorted { $0.t < $1.t }
            for (i, mark) in sorted.enumerated() {
                let want: Presence = mark.arrive ? .inside : .outside
                let budget = mark.arrive ? arriveWithin : leaveWithin
                let hit = changes.first { $0.presence == want && $0.t >= mark.t - slack }
                if let hit, hit.t <= mark.t + budget + slack {
                    // fine
                } else {
                    let late = hit.map { "after \(Int($0.t - mark.t)) s" } ?? "never"
                    problems.append("\(place) \(mark.arrive ? "arrive" : "leave") at \(Int(mark.t)) s: engine \(late)")
                }
                // Between this mark (plus its budget) and the next, the opposite must not happen.
                let from = mark.t + budget + slack
                let to = (i + 1 < sorted.count ? sorted[i + 1].t : .infinity) - slack
                let wrong: Presence = mark.arrive ? .outside : .inside
                for c in changes where c.presence == wrong && c.t > from && c.t < to {
                    problems.append("\(place): \(mark.arrive ? "blocked while inside" : "unblocked while outside") at \(Int(c.t)) s (\(c.reason))")
                }
            }
        }
        return problems
    }

    private final class Token {}
}

// MARK: - ReplayTrace files

/// A fixture: places, readings and truth, in time order.
struct ReplayTrace {
    enum Event {
        case places([Place])
        case reading(PresenceRules.Reading, at: TimeInterval)
    }

    var events: [Event] = []
    var truth: [TraceReplayTests.Truth] = []
    /// Fixture times are seconds from this.
    static let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() {}

    init(url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var names: [String: String] = [:] // place id -> name, for geofence lines
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let kind = obj["kind"] as? String, let t = obj["t"] as? Double else { continue }
            switch kind {
            case "places":
                let places = (obj["places"] as? [[String: Any]] ?? []).compactMap { p -> Place? in
                    guard let id = (p["id"] as? String).flatMap(UUID.init), let name = p["name"] as? String,
                          let lat = p["lat"] as? Double, let lon = p["lon"] as? Double,
                          let radius = p["radius"] as? Double else { return nil }
                    names[id.uuidString] = name
                    var place = Place(id: id, name: name, latitude: lat, longitude: lon, radius: radius)
                    place.activeAfter = (p["activeAfter"] as? Double).map { Self.base.addingTimeInterval($0) }
                    return place
                }
                events.append(.places(places))
            case "fix":
                guard let lat = obj["lat"] as? Double, let lon = obj["lon"] as? Double,
                      let acc = obj["acc"] as? Double, let fixT = obj["fixT"] as? Double else { continue }
                let fix = Fix(latitude: lat, longitude: lon, accuracy: acc, speed: obj["speed"] as? Double ?? -1,
                              at: Self.base.addingTimeInterval(fixT))
                events.append(.reading(.fix(fix), at: t))
            case "geofence":
                guard let id = (obj["place"] as? String).flatMap(UUID.init),
                      let presence = (obj["presence"] as? String).flatMap(Presence.init),
                      let eventT = obj["eventT"] as? Double else { continue }
                events.append(.reading(.geofence(id, presence, at: Self.base.addingTimeInterval(eventT)), at: t))
            case "truth":
                guard let place = obj["place"] as? String, let event = obj["event"] as? String else { continue }
                truth.append(.init(t: t, place: place, arrive: event == "arrive"))
            default:
                continue
            }
        }
    }
}

// MARK: - Replaying

enum Replay {
    struct Transition: Equatable {
        var t: TimeInterval
        var place: String
        var presence: Presence
        var reason: String
    }

    /// Feeds every reading through `PresenceRules` at the time it arrived, keeping each place's
    /// state by its circle (as `LocationEngine` does), and lists each change of presence.
    static func run(_ trace: ReplayTrace) -> [Transition] {
        var places: [Place] = []
        var states: [String: PresenceRules.PlaceState] = [:]
        var out: [Transition] = []
        for event in trace.events {
            switch event {
            case .places(let new):
                places = new
                let keys = Set(new.map(GeofenceKeys.key(for:)))
                states = states.filter { keys.contains($0.key) }
            case .reading(let reading, let t):
                let now = ReplayTrace.base.addingTimeInterval(t)
                for place in places {
                    let key = GeofenceKeys.key(for: place)
                    let old = states[key] ?? .init()
                    let new = PresenceRules.step(old, place: place, reading: reading, now: now)
                    states[key] = new
                    if new.presence != old.presence {
                        out.append(.init(t: t, place: place.name, presence: new.presence, reason: new.reason?.rawValue ?? ""))
                    }
                }
            }
        }
        return out
    }
}

// MARK: - Made-up traces

/// Seeded, so every run is the same.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 { // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum Synthetic {
    /// Walk in from 400 m out (GPS), stay 3 h at a spot 30% of the radius from the center with
    /// indoor fixes (mostly Wi-Fi, ±30–65 m, now and then kilometers off, now and then a
    /// GPS-grade fix by a window), then walk out to 400 m (GPS).
    static func stay(radius: Double, seed: UInt64) -> ReplayTrace {
        var rng = SeededRandom(seed)
        let place = Place(name: "Home", latitude: 37.7694, longitude: -122.4862, radius: radius)
        var trace = ReplayTrace()
        trace.events.append(.places([place]))
        func gauss() -> Double {
            let u1 = Double.random(in: 0.000_001..<1, using: &rng), u2 = Double.random(in: 0..<1, using: &rng)
            return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
        }
        func add(t: TimeInterval, north: Double, east: Double, acc: Double, speed: Double = -1) {
            let lat = place.latitude + north / 111_320
            let lon = place.longitude + east / (111_320 * cos(place.latitude * .pi / 180))
            let fix = Fix(latitude: lat, longitude: lon, accuracy: acc, speed: speed, at: ReplayTrace.base.addingTimeInterval(t))
            trace.events.append(.reading(.fix(fix), at: t + 0.5))
        }
        let walk = 1.4
        var t: TimeInterval = 0
        // In: 400 m north to 0.3 × radius, a GPS fix every 2 s.
        let spot = radius * 0.3
        var d = 400.0
        while d > spot {
            add(t: t, north: d + gauss() * 4, east: gauss() * 4, acc: Double.random(in: 5...12, using: &rng), speed: walk)
            if d > radius, d - walk * 2 <= radius { trace.truth.append(.init(t: t + (d - radius) / walk, place: "Home", arrive: true)) }
            d -= walk * 2
            t += 2
        }
        // Stay: a fix about once a minute while moving around inside.
        let stayEnd = t + 3 * 3600
        while t < stayEnd {
            t += Double.random(in: 20...120, using: &rng)
            let roll = Double.random(in: 0..<1, using: &rng)
            if roll < 0.02 {
                // Wi-Fi mislocation: kilometers off, but claims ±40–65 m.
                let far = Double.random(in: 1_000...3_000, using: &rng), angle = Double.random(in: 0..<(2 * .pi), using: &rng)
                add(t: t, north: far * cos(angle), east: far * sin(angle), acc: Double.random(in: 40...65, using: &rng))
            } else if roll < 0.10 {
                // GPS by a window: good, but drifts a little.
                add(t: t, north: spot + gauss() * 10, east: gauss() * 10, acc: Double.random(in: 15...28, using: &rng))
            } else {
                let acc = Double.random(in: 30...65, using: &rng)
                add(t: t, north: spot + gauss() * acc / 2, east: gauss() * acc / 2, acc: acc)
            }
        }
        // Out: back to 400 m north, GPS every 2 s.
        d = spot
        while d < 400 {
            add(t: t, north: d + gauss() * 4, east: gauss() * 4, acc: Double.random(in: 5...12, using: &rng), speed: walk)
            if d <= radius, d + walk * 2 > radius { trace.truth.append(.init(t: t + (radius - d) / walk, place: "Home", arrive: false)) }
            d += walk * 2
            t += 2
        }
        return trace
    }
}
