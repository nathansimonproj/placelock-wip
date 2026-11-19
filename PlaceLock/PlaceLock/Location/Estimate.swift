import CoreLocation
import Foundation

/// Names where the phone thinks it is, for the block screen's "Estimated @" line.
enum EstimateRules {
    /// A saved place you're inside wins, then the map's name for the spot ("Suzzallo Library",
    /// "4700 Brooklyn Ave NE"), then the distance to the nearest saved place ("400 m from Gym").
    static func label(at here: CLLocation, places: [Place], mapName: String?) -> String? {
        if let inside = places.filter({ $0.distanceOutside(here) <= 0 })
            .min(by: { $0.distanceOutside(here) < $1.distanceOutside(here) }) {
            return inside.name
        }
        if let mapName = mapName?.trimmingCharacters(in: .whitespaces), !mapName.isEmpty {
            return mapName
        }
        guard let nearest = places.min(by: { $0.distanceOutside(here) < $1.distanceOutside(here) }) else {
            return nil
        }
        return "\(distance(here.distance(from: nearest.location))) from \(nearest.name)"
    }

    /// "80 m", "400 m", "1.2 km", "12 km".
    static func distance(_ meters: Double) -> String {
        switch meters {
        case ..<100: "\(Int((meters / 10).rounded()) * 10) m"
        case ..<1000: "\(Int((meters / 50).rounded()) * 50) m"
        case ..<10_000: String(format: "%.1f km", meters / 1000)
        default: "\(Int((meters / 1000).rounded())) km"
        }
    }
}

extension AppModel {
    /// Saves a fresh "Estimated @" for the block screen. Runs after reconciles, at most once a
    /// minute, and never holds up locking: a fix can take a few seconds.
    func refreshEstimate() {
        guard estimateTask == nil, Date.now.timeIntervalSince(lastEstimateAttempt) > 60 else { return }
        lastEstimateAttempt = .now
        estimateTask = Task { @MainActor in
            defer { estimateTask = nil }
            guard let label = await currentEstimateLabel() else { return }
            SharedStore.estimate = .init(label: label, at: .now)
            Log.app.info("Estimated @ \(label, privacy: .private)")
        }
    }

    private func currentEstimateLabel() async -> String? {
        switch simulatedSpot { // Debug's "Pretend I'm at…"
        case .place(let id): return places.first { $0.id == id }?.name
        case .elsewhere: return "somewhere else (pretend)"
        case nil: break
        }
        if let activePlace { return activePlace.name } // unlocked: iOS already says where you are
        // 200 m is enough to name a building or street, and comes quickly from Wi-Fi.
        guard let here = try? await location.currentLocation(maxAccuracy: 200, timeout: 10) else { return nil }
        let mapName = try? await CLGeocoder().reverseGeocodeLocation(here).first?.name
        return EstimateRules.label(at: here, places: places, mapName: mapName)
    }
}
