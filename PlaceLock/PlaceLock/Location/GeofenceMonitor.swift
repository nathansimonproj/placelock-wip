import CoreLocation

/// Watches every saved place and reports when the user enters or leaves one.
/// iOS relaunches the app in the background for these events, so `start` runs on every launch.
/// CLMonitor allows at most 20 conditions per app, so that's the cap on saved places. Whatever
/// the places leave over goes to approach rings (`GeofenceKeys.ringed`), which wake the app early.
///
/// Each circle is watched under `GeofenceKeys.key(for:)`, which carries its geometry (see
/// Models/Rules.swift). Those identifiers include coordinates, so logs show only the place's UUID.
actor GeofenceMonitor {
    static let shared = GeofenceMonitor()
    static let maxPlaces = 20
    private static let monitorName = "PlaceLockMonitor"

    /// Created once. iOS aborts if two monitors share a name, and actor calls can overlap while
    /// the first one is being created, so every caller awaits this same task.
    private var monitor: Task<CLMonitor, Never>?

    private func get() async -> CLMonitor {
        if let monitor { return await monitor.value }
        let task = Task { await CLMonitor(Self.monitorName) }
        monitor = task
        return await task.value
    }

    /// Latest event per identifier as delivered to us. The monitor's stored record can lag the
    /// event stream by a few ms, so a fresh event wins over an older record.
    private var latest: [String: CLMonitor.Event] = [:]

    private func remember(_ event: CLMonitor.Event) {
        latest[event.identifier] = event
    }

    /// The UUID part of an identifier, safe for public logs (no coordinates).
    private static func logID(_ identifier: String) -> String {
        GeofenceKeys.isRing(identifier) ? "ring " + String(identifier.dropFirst(GeofenceKeys.ringPrefix.count).prefix(36))
            : String(identifier.prefix(36))
    }

    /// One event, reduced to what `LocationEngine` uses.
    struct Event: Sendable {
        var placeID: UUID?
        /// An approach ring, not the place itself.
        var ring: Bool
        var presence: Presence
        var date: Date
    }

    /// Starts listening and calls `onChange` after every enter or exit event.
    func start(onChange: @escaping @Sendable (Event) async -> Void) async {
        let m = await get()
        Task {
            do {
                for try await event in await m.events {
                    Log.app.notice("Geofence \(Self.logID(event.identifier), privacy: .public): \(String(describing: event.state), privacy: .public)")
                    if #available(iOS 18.0, *) { Self.logLimits(event) }
                    self.remember(event)
                    await onChange(Event(placeID: GeofenceKeys.placeID(from: event.identifier),
                                         ring: GeofenceKeys.isRing(event.identifier),
                                         presence: Presence(event.state), date: event.date))
                }
            } catch {
                Log.app.error("GeofenceMonitor events ended: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Logs anything iOS says is stopping it from watching a place (iOS 18 adds these flags).
    @available(iOS 18.0, *)
    private static func logLimits(_ e: CLMonitor.Event) {
        let flags = [
            ("accuracyLimited", e.accuracyLimited),
            ("conditionLimitExceeded", e.conditionLimitExceeded),
            ("conditionUnsupported", e.conditionUnsupported),
            ("persistenceUnavailable", e.persistenceUnavailable),
            ("insufficientlyInUse", e.insufficientlyInUse),
            ("serviceSessionRequired", e.serviceSessionRequired),
            ("authorizationDenied", e.authorizationDenied),
            ("authorizationDeniedGlobally", e.authorizationDeniedGlobally),
            ("authorizationRestricted", e.authorizationRestricted),
            ("authorizationRequestInProgress", e.authorizationRequestInProgress),
        ].filter(\.1).map(\.0)
        guard !flags.isEmpty else { return }
        Log.app.error("Geofence \(logID(e.identifier), privacy: .public) limited: \(flags.joined(separator: ", "), privacy: .public)")
    }

    /// Make the monitored circles match `places`. Unchanged circles are left alone and keep their
    /// state. New or changed ones start as unknown, and iOS reports whether you're inside shortly
    /// after. Called only from `AppModel.reconcileNow`, so two syncs never overlap.
    func sync(_ places: [Place]) async {
        let m = await get()
        let plan = GeofenceKeys.diff(current: await m.identifiers, places: places, max: Self.maxPlaces, rings: true)
        guard !plan.isEmpty else { return }
        let wantedIDs = Set(places.map(\.id.uuidString))
        // Removes first: iOS allows 20 conditions, and the adds can be a whole new set (the first
        // launch after identifiers started carrying geometry replaces every one).
        for identifier in plan.remove {
            await m.remove(identifier)
            latest[identifier] = nil
            let id = Self.logID(identifier)
            let placeID = GeofenceKeys.placeID(from: identifier)?.uuidString ?? ""
            let reason = !identifier.contains("@") ? "old identifier"
                : wantedIDs.contains(placeID) ? (GeofenceKeys.isRing(identifier) ? "ring no longer fits" : "moved or resized") : "deleted"
            Log.app.notice("Geofence \(id, privacy: .public) removed (\(reason, privacy: .public))")
        }
        for place in plan.add {
            let key = GeofenceKeys.key(for: place)
            latest[key] = nil // an edit back to an earlier circle mustn't reuse that circle's old event
            await m.add(CLMonitor.CircularGeographicCondition(center: place.coordinate, radius: place.radius),
                        identifier: key)
            Log.app.notice("Geofence \(place.id.uuidString, privacy: .public) added (r=\(Int(place.radius)) m)")
        }
        for place in plan.addRings {
            let key = GeofenceKeys.ringKey(for: place)
            latest[key] = nil
            await m.add(CLMonitor.CircularGeographicCondition(center: place.coordinate,
                                                              radius: place.radius + GeofenceKeys.ringExtra),
                        identifier: key)
            Log.app.notice("Geofence ring \(place.id.uuidString, privacy: .public) added (r=\(Int(place.radius + GeofenceKeys.ringExtra)) m)")
        }
    }

    /// iOS's latest reading for each watched place, with the date iOS gave it.
    func readings(for places: [Place]) async -> [UUID: (presence: Presence, date: Date)] {
        let m = await get()
        var result: [UUID: (presence: Presence, date: Date)] = [:]
        for place in GeofenceKeys.watched(places, max: Self.maxPlaces) {
            let key = GeofenceKeys.key(for: place)
            guard let record = await m.record(for: key) else { continue }
            var event = record.lastEvent
            if let fresh = latest[key], fresh.date >= event.date { event = fresh }
            result[place.id] = (Presence(event.state), event.date)
        }
        return result
    }

    /// iOS's latest reading for each watched place. A place with no record gets no reading.
    func states(for places: [Place]) async -> [UUID: CLMonitor.Event.State] {
        let m = await get()
        var result: [UUID: CLMonitor.Event.State] = [:]
        for place in GeofenceKeys.watched(places, max: Self.maxPlaces) {
            let key = GeofenceKeys.key(for: place)
            guard let record = await m.record(for: key) else { continue }
            var event = record.lastEvent
            if let fresh = latest[key], fresh.date >= event.date { event = fresh }
            result[place.id] = event.state
        }
        return result
    }
}

extension Presence {
    /// `.unmonitored` (iOS 18) counts as unknown, like anything else that isn't a clear answer.
    init(_ state: CLMonitor.Event.State) {
        switch state {
        case .satisfied: self = .inside
        case .unsatisfied: self = .outside
        default: self = .unknown
        }
    }
}
