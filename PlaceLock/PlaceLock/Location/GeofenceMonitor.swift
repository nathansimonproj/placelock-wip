import CoreLocation

/// Watches every saved place and reports when the user enters or leaves one.
/// iOS relaunches the app in the background for these events, so `start` runs on every launch.
/// CLMonitor allows at most 20 conditions per app, so that's the cap on saved places.
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

    /// Latest event per place as delivered to us. The monitor's stored record can lag the
    /// event stream by a few ms, so a fresh event wins over an older record.
    private var latest: [String: CLMonitor.Event] = [:]

    private func remember(_ event: CLMonitor.Event) {
        latest[event.identifier] = event
    }

    /// Starts listening and calls `onChange` after every enter or exit event.
    func start(onChange: @escaping @Sendable () async -> Void) async {
        let m = await get()
        Task {
            do {
                for try await event in await m.events {
                    Log.app.info("Geofence \(event.identifier, privacy: .public): \(String(describing: event.state), privacy: .public)")
                    await self.remember(event)
                    await onChange()
                }
            } catch {
                Log.app.error("GeofenceMonitor events ended: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Make the monitored circles match `places`. Unchanged places keep their current state.
    /// New ones start as unknown, and iOS reports whether you're inside shortly after.
    func sync(_ places: [Place]) async {
        let m = await get()
        let wanted = Dictionary(uniqueKeysWithValues: places.prefix(Self.maxPlaces).map { ($0.id.uuidString, $0) })
        for id in await m.identifiers {
            guard let place = wanted[id],
                  let circle = await m.record(for: id)?.condition as? CLMonitor.CircularGeographicCondition,
                  circle.center.latitude == place.latitude, circle.center.longitude == place.longitude,
                  circle.radius == place.radius
            else {
                await m.remove(id)
                latest[id] = nil
                continue
            }
        }
        let existing = Set(await m.identifiers)
        for (id, place) in wanted where !existing.contains(id) {
            await m.add(CLMonitor.CircularGeographicCondition(center: place.coordinate, radius: place.radius),
                        identifier: id)
        }
    }

    /// iOS's latest reading for each monitored place.
    func states() async -> [UUID: CLMonitor.Event.State] {
        let m = await get()
        var result: [UUID: CLMonitor.Event.State] = [:]
        for id in await m.identifiers {
            guard let uuid = UUID(uuidString: id), let record = await m.record(for: id) else { continue }
            var event = record.lastEvent
            if let fresh = latest[id], fresh.date >= event.date { event = fresh }
            result[uuid] = event.state
        }
        return result
    }
}

extension Presence {
    init(_ state: CLMonitor.Event.State) {
        switch state {
        case .satisfied: self = .inside
        case .unsatisfied: self = .outside
        default: self = .unknown
        }
    }
}
