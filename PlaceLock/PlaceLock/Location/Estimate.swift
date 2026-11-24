import CoreLocation
import Foundation
import UIKit

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
    /// minute with the app open and every 5 minutes in the background (a move or a lock change
    /// still estimates right away), and never holds up locking: a fix can take a few seconds.
    func refreshEstimate() {
        let gap: TimeInterval = UIApplication.shared.applicationState == .active ? 60 : 300
        guard estimateTask == nil, Date.now.timeIntervalSince(lastEstimateAttempt) > gap else { return }
        lastEstimateAttempt = .now
        estimateTask = Task { @MainActor in
            defer { estimateTask = nil }
            guard let label = await currentEstimateLabel() else { return }
            SharedStore.estimate = .init(label: label, at: .now)
            Log.app.info("Estimated @ \(label, privacy: .private)")
        }
    }

    private func currentEstimateLabel() async -> String? {
        #if DEBUG
        switch simulatedSpot { // Debug's "Pretend I'm at…"
        case .place(let id): return places.first { $0.id == id }?.name
        case .elsewhere: return "somewhere else (pretend)"
        case nil: break
        }
        #endif
        if let activePlace { return activePlace.name } // unlocked: iOS already says where you are
        // 200 m is enough to name a building or street. Battery: if the move that woke the app is
        // already that good, use it instead of turning on GPS; in Low Power Mode never turn it on.
        // Otherwise ask for a fix, and after 5 s (a background wake is short) fall back to the move.
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        // The engine's latest fix (tracking near places) or the last ~500 m move, whichever is newer.
        let newest = [engine.lastLocation, lastMove].compactMap { $0 }.max { $0.timestamp < $1.timestamp }
        let recentMove = newest.flatMap { -$0.timestamp.timeIntervalSinceNow < 300 ? $0 : nil }
        var here = recentMove.flatMap { $0.horizontalAccuracy >= 0 && ($0.horizontalAccuracy <= 200 || lowPower) ? $0 : nil }
        if here == nil, !lowPower {
            here = try? await location.currentLocation(maxAccuracy: 200, timeout: 5)
        }
        guard let here = here ?? recentMove else { return nil }
        return EstimateRules.label(at: here, places: places, mapName: await mapName(at: here))
    }

    /// Apple Maps' name for the spot, reusing the last answer within 100 m of it. Failures
    /// (offline, rate-limited) aren't remembered, so the next estimate tries again.
    private func mapName(at here: CLLocation) async -> String? {
        if let last = lastGeocode, last.location.distance(from: here) < 100 { return last.name }
        guard let marks = try? await CLGeocoder().reverseGeocodeLocation(here) else { return nil }
        let name = marks.first?.name
        lastGeocode = (here, name)
        return name
    }
}
