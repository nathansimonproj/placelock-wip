import CoreLocation
import Foundation
import UIKit

/// The new location logic (2026-11-23): Cove's own fixes decide inside and outside for every
/// place (`PresenceRules`), and how hard to track comes from `TrackingPolicy`. iOS's geofences,
/// approach rings, ~500 m movement wakes and visits wake the app and serve as a fallback.
///
/// In `.shadow` (the default for now) it runs next to the current geofence logic and only
/// records what it would decide (`AppModel.runShadow`, `Trace`). In `.live` its presence decides.
@MainActor
final class LocationEngine: NSObject, CLLocationManagerDelegate {
    enum Mode: String, CaseIterable {
        case shadow, live
    }

    /// Saved setting. Debug builds also take `-engineMode live|shadow` on the command line.
    var mode: Mode {
        get {
            #if DEBUG
            if let arg = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["engineMode"] as? String,
               let m = Mode(rawValue: arg) { return m }
            #endif
            return Storage.defaults.string(forKey: Keys.mode).flatMap(Mode.init) ?? .shadow
        }
        set {
            Storage.defaults.set(newValue.rawValue, forKey: Keys.mode)
            Log.app.notice("Location engine: \(newValue.rawValue, privacy: .public)")
            onChange?()
        }
    }

    /// Called when any place's presence changes (and when the mode changes).
    var onChange: (() -> Void)?

    private(set) var tracking: TrackingPolicy.Mode = .dormant
    /// Per place, keyed by `GeofenceKeys.key(for:)` so moving or resizing a place starts it fresh.
    private var states: [String: PresenceRules.PlaceState] = [:]
    private var places: [Place] = []
    /// The newest fix from any source, for distances and for "Estimated @".
    private(set) var lastLocation: CLLocation?
    private var lastDelivered: Date?
    private var burstStartedAt: Date?
    private var exitHint = false
    /// A short best-accuracy check (opening Cove, a visit, a ring) runs until this time.
    private var checkUntil: Date?
    private var checkTask: UIBackgroundTaskIdentifier = .invalid
    private var timer: Task<Void, Never>?
    private var updating = false
    private var canTrack: () -> Bool = { false }

    private let manager = CLLocationManager()

    private enum Keys {
        static let mode = "engineMode", states = "engineStates"
    }

    /// Fixes stop counting as "still moving" after this.
    static let stationaryAfter: TimeInterval = 60
    /// How long a check on opening Cove, a visit or a ring runs at best accuracy.
    static let checkLength: TimeInterval = 20

    override init() {
        super.init()
        manager.delegate = self
        manager.pausesLocationUpdatesAutomatically = false // the policy decides; iOS wouldn't resume
        manager.activityType = .other
        manager.showsBackgroundLocationIndicator = false // Always apps then get no blue pill
        if let data = Storage.defaults.data(forKey: Keys.states),
           let saved = try? JSONDecoder().decode([String: PresenceRules.PlaceState].self, from: data) {
            states = saved
        }
    }

    // MARK: Inputs

    /// Runs on every launch. `canTrack` is Always plus Precise Location.
    func start(places: [Place], canTrack: @escaping () -> Bool) {
        self.canTrack = canTrack
        placesChanged(places)
        if canTrack() { manager.startMonitoringVisits() } // relaunches Cove after a force-quit too
        Trace.note("engine started (\(mode.rawValue), \(places.count) places)")
        // Where you are isn't kept across launches, and without it the policy can only say
        // dormant. One short look finds out (a wake that brought a fix replaces it at once).
        if !places.isEmpty { check("launch") } else { updatePolicy() }
    }

    func placesChanged(_ newPlaces: [Place]) {
        if newPlaces != places { Trace.places(newPlaces) }
        places = newPlaces
        let keys = Set(newPlaces.map(GeofenceKeys.key(for:)))
        let before = states.count
        states = states.filter { keys.contains($0.key) }
        if states.count != before { save() }
        updatePolicy()
    }

    /// Permission changed: start or stop everything.
    func permissionChanged() {
        if canTrack() { manager.startMonitoringVisits() } else { manager.stopMonitoringVisits() }
        updatePolicy()
    }

    /// iOS's stored readings at launch, as fallback evidence (older than any change: ignored).
    func seed(_ readings: [UUID: (presence: Presence, date: Date)]) {
        for (id, r) in readings {
            apply(.geofence(id, r.presence, at: r.date), now: .now)
        }
    }

    /// A fix from the ~500 m movement wakes (or anywhere else outside this engine).
    func fix(_ location: CLLocation, source: String) {
        take(location, source: source)
    }

    func geofence(_ event: GeofenceMonitor.Event) {
        Trace.geofence(event)
        guard let id = event.placeID else { return }
        if event.ring {
            if event.presence == .inside { check("ring") } // heading for a place: look now
            return
        }
        let wasInside = presence[id] == .inside
        apply(.geofence(id, event.presence, at: event.date), now: .now)
        if wasInside, event.presence == .outside {
            exitHint = true // iOS thinks you left: look closely before (or after) it applies
            check("iOS exit")
        } else if event.presence == .inside, presence[id] != .inside {
            check("iOS entry")
        }
        updatePolicy()
    }

    /// A short best-accuracy look, for at most `checkLength` seconds, even in the background.
    func check(_ why: String) {
        guard canTrack() else { return }
        checkUntil = Date.now.addingTimeInterval(Self.checkLength)
        if checkTask == .invalid {
            checkTask = UIApplication.shared.beginBackgroundTask(withName: "location check") { [weak self] in
                self?.endCheck()
            }
        }
        Trace.note("check: \(why)")
        updatePolicy()
    }

    // MARK: Output

    var presence: [UUID: Presence] {
        var result: [UUID: Presence] = [:]
        for place in places { result[place.id] = states[GeofenceKeys.key(for: place)]?.presence ?? .unknown }
        return result
    }

    func state(for place: Place) -> PresenceRules.PlaceState? { states[GeofenceKeys.key(for: place)] }

    // MARK: Core

    private func take(_ location: CLLocation, source: String) {
        let fix = Fix(location)
        Trace.fix(fix, source: source)
        if lastLocation.map({ location.timestamp >= $0.timestamp }) ?? true { lastLocation = location }
        // Only a fresh fix says you're moving now (a movement wake can hand over one from long ago).
        let fresh = Date.now.timeIntervalSince(location.timestamp) <= PresenceRules.maxFixAge
        let resumed = fresh && (lastDelivered.map { Date.now.timeIntervalSince($0) >= Self.stationaryAfter } ?? true)
        if fresh { lastDelivered = .now }
        apply(.fix(fix), now: .now)
        updatePolicy(resumed: resumed && source == "tracking", speed: fix.speed)
    }

    private func apply(_ reading: PresenceRules.Reading, now: Date) {
        var changed = false
        for place in places {
            let key = GeofenceKeys.key(for: place)
            let old = states[key] ?? .init()
            let new = PresenceRules.step(old, place: place, reading: reading, now: now)
            guard new != old else { continue }
            states[key] = new
            if new.presence != old.presence {
                changed = true
                dirty = true
                Trace.presence(place, new)
                Log.app.notice("Engine: \(place.name, privacy: .private) \(new.presence.rawValue, privacy: .public) (\(new.reason?.rawValue ?? "", privacy: .public))")
            }
        }
        // A burst brings a fix a second: save presence changes at once, the rest (pairs waiting
        // for their second fix) at most every 30 s.
        if dirty || Date.now.timeIntervalSince(lastSave) >= 30 { save() }
        if changed { onChange?() }
    }

    private var dirty = false
    private var lastSave = Date.distantPast

    /// Picks the tracking mode and applies it to Core Location.
    private func updatePolicy(resumed: Bool = false, speed: Double = -1) {
        guard canTrack() else {
            setTracking(.dormant, settings: TrackingPolicy.settings(for: .dormant, lowPower: false))
            return
        }
        let now = Date.now
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let here = lastLocation.flatMap { now.timeIntervalSince($0.timestamp) < 600 ? $0 : nil }
        let insidePlaces = places.filter { states[GeofenceKeys.key(for: $0)]?.presence == .inside }
        // Inside: the place whose edge you'd reach first. Outside: the nearest edge.
        let relevant = here.flatMap { loc in
            (insidePlaces.isEmpty ? places : insidePlaces).max { a, b in
                insidePlaces.isEmpty ? a.distanceOutside(loc) > b.distanceOutside(loc)
                    : a.distanceOutside(loc) < b.distanceOutside(loc)
            }
        }
        let stationary = lastDelivered.map { now.timeIntervalSince($0) >= Self.stationaryAfter } ?? true
        var mode = TrackingPolicy.mode(.init(
            distanceToEdge: here.flatMap { loc in relevant.map { $0.distanceOutside(loc) } },
            radius: relevant?.radius ?? 100,
            inside: !insidePlaces.isEmpty,
            stationary: stationary && !resumed,
            resumed: resumed, speed: speed, exitHint: exitHint,
            burstStartedAt: burstStartedAt, lowPower: lowPower, previous: tracking, now: now))
        exitHint = false
        if mode == .burst, tracking != .burst { burstStartedAt = now }
        if mode != .burst { burstStartedAt = nil }

        var settings = TrackingPolicy.settings(for: mode, lowPower: lowPower)
        if let until = checkUntil {
            if until > now {
                settings = TrackingPolicy.settings(for: .edge, lowPower: false)
                if mode == .dormant || mode == .approach { mode = .edge }
            } else {
                endCheck()
            }
        }
        setTracking(mode, settings: settings)
    }

    private func setTracking(_ mode: TrackingPolicy.Mode, settings: TrackingPolicy.Settings) {
        if mode != tracking {
            Trace.mode(mode, background: UIApplication.shared.applicationState != .active)
            Log.app.info("Tracking: \(mode.rawValue, privacy: .public)")
            tracking = mode
        }
        if settings.running {
            manager.desiredAccuracy = settings.accuracy
            manager.distanceFilter = settings.distanceFilter
            if !updating {
                manager.allowsBackgroundLocationUpdates = true // UIBackgroundModes has "location"
                manager.startUpdatingLocation()
                updating = true
                // Open question for the iPhone: does this work when started from a background wake?
                Trace.note("updates started (\(UIApplication.shared.applicationState == .active ? "front" : "back"))")
            }
            startTimer()
        } else if updating {
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
            updating = false
            timer?.cancel()
            timer = nil
            Trace.note("updates stopped")
        }
    }

    /// While tracking, re-pick the mode every 20 s, so bursts end and stillness is noticed even
    /// when no fixes arrive (the distance filter holds them back while you sit still).
    private func startTimer() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, let self else { return }
                self.heartbeat()
                self.updatePolicy()
            }
        }
    }

    private var lastHeartbeat = Date.distantPast

    /// Shows in the trace whether iOS keeps Cove running in the background while it tracks
    /// (at most once a minute). Gaps mean iOS suspended it.
    private func heartbeat() {
        guard UIApplication.shared.applicationState != .active, Date.now.timeIntervalSince(lastHeartbeat) >= 60 else { return }
        lastHeartbeat = .now
        Trace.note("alive in background (\(tracking.rawValue))")
    }

    private func endCheck() {
        checkUntil = nil
        if checkTask != .invalid {
            UIApplication.shared.endBackgroundTask(checkTask)
            checkTask = .invalid
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(states) { Storage.defaults.set(data, forKey: Keys.states) }
        dirty = false
        lastSave = .now
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations { self.take(location, source: "tracking") }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let lat = visit.coordinate.latitude, lon = visit.coordinate.longitude, acc = visit.horizontalAccuracy
        let arrival = visit.arrivalDate == .distantPast ? nil : visit.arrivalDate
        let departure = visit.departureDate == .distantFuture ? nil : visit.departureDate
        Task { @MainActor in
            Trace.visit(lat: lat, lon: lon, accuracy: acc, arrival: arrival, departure: departure)
            // Visits are coarse and late: a reason to look, never evidence on their own.
            self.check(departure == nil ? "visit arrival" : "visit departure")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in Trace.note("tracking error: \(error.localizedDescription)") }
    }
}
