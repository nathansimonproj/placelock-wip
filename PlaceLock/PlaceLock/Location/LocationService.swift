import CoreLocation

enum LocationError: LocalizedError {
    case notAuthorized
    case noAccurateFix

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "Location access is off. Allow it in Settings › PlaceLock › Location."
        case .noAccurateFix: "Couldn't get an accurate location. Try again near a window or outside."
        }
    }
}

/// Location permission plus a one-shot accurate fix.
@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorization: CLAuthorizationStatus

    private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var hasAlways: Bool { authorization == .authorizedAlways }

    /// iOS asks for "While Using" first; asking for Always afterwards upgrades it.
    func requestPermission() {
        switch authorization {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            // Chain straight into the Always prompt after While Using is granted.
            if status == .authorizedWhenInUse { self.manager.requestAlwaysAuthorization() }
        }
    }

    /// First fix with accuracy of `maxAccuracy` meters or better, within `timeout` seconds.
    func currentLocation(maxAccuracy: Double = 100, timeout: Double = 15) async throws -> CLLocation {
        guard authorization == .authorizedAlways || authorization == .authorizedWhenInUse else {
            throw LocationError.notAuthorized
        }
        return try await withThrowingTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if let loc = update.location, loc.horizontalAccuracy >= 0,
                       loc.horizontalAccuracy <= maxAccuracy {
                        return loc
                    }
                }
                return nil
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            guard let first else { throw LocationError.noAccurateFix }
            return first
        }
    }
}
