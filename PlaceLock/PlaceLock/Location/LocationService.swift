import CoreLocation

enum LocationError: LocalizedError {
    case notAuthorized
    case noAccurateFix

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "Location access is off. Allow it in Settings › Cove › Location."
        case .noAccurateFix: "Couldn't get an accurate location. Try again near a window or outside."
        }
    }
}

/// Location permission plus a one-shot accurate fix.
@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorization: CLAuthorizationStatus
    /// Precise Location (Settings › PlaceLock › Location). With it off, iOS gives only a rough
    /// area and won't watch places at all, so nothing ever unlocks.
    @Published private(set) var isPrecise: Bool

    private let manager = CLLocationManager()
    private var onMove: ((CLLocation) -> Void)?
    /// Called after `authorization` or `isPrecise` really changed, so a running app reconciles at
    /// once. Not called for the callback iOS sends on every launch, which repeats the same values.
    var onAuthorizationChange: (() -> Void)?
    /// A `CLServiceSession` asking for Always (iOS 18+). Without one, Core Location treats the
    /// app's geofence events as When In Use, and arriving somewhere didn't unblock apps until the
    /// app was opened. Created as soon as Always is granted and on every launch, including the
    /// background relaunches iOS does for geofence events, as Apple's docs require.
    private var alwaysSession: AnyObject?

    override init() {
        authorization = manager.authorizationStatus
        isPrecise = Self.readPrecise(manager)
        super.init()
        manager.delegate = self
        holdAlwaysSessionIfAllowed()
    }

    private func holdAlwaysSessionIfAllowed() {
        guard #available(iOS 18.0, *), alwaysSession == nil, authorization == .authorizedAlways else { return }
        let session = CLServiceSession(authorization: .always)
        alwaysSession = session
        Log.app.info("Holding an Always location session")
        Task {
            // Log only what would stop background events, to debug from the phone's logs.
            for try await d in session.diagnostics where d.insufficientlyInUse || d.serviceSessionRequired
                || d.alwaysAuthorizationDenied || d.fullAccuracyDenied || d.authorizationDenied {
                Log.app.error("Location session limited: inUse=\(d.insufficientlyInUse) sessionRequired=\(d.serviceSessionRequired) alwaysDenied=\(d.alwaysAuthorizationDenied) fullAccuracyDenied=\(d.fullAccuracyDenied) denied=\(d.authorizationDenied)")
            }
        }
    }

    nonisolated private static func readPrecise(_ manager: CLLocationManager) -> Bool {
        #if DEBUG
        // `-preciseOff YES` pretends Precise Location is off, which `simctl privacy` can't set.
        if UserDefaults.standard.bool(forKey: "preciseOff") { return false }
        #endif
        return manager.accuracyAuthorization == .fullAccuracy
    }

    var hasAlways: Bool { authorization == .authorizedAlways }

    /// Everything automatic unlocking needs: Always, and Precise Location on.
    var canWatchPlaces: Bool { hasAlways && isPrecise }

    /// Location is allowed, but Precise Location is off.
    var needsPrecise: Bool {
        (authorization == .authorizedAlways || authorization == .authorizedWhenInUse) && !isPrecise
    }

    /// iOS asks for "While Using" first; asking for Always afterwards upgrades it.
    func requestPermission() {
        switch authorization {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    private var decisionWaiters: [CheckedContinuation<Void, Never>] = []

    /// Returns once the user has answered the location prompt (right away if they already have).
    func waitForDecision() async {
        guard authorization == .notDetermined else { return }
        await withCheckedContinuation { decisionWaiters.append($0) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let precise = Self.readPrecise(manager)
        Task { @MainActor in
            let changed = status != self.authorization || precise != self.isPrecise
            self.authorization = status
            if precise != self.isPrecise {
                Log.app.info("Precise Location \(precise ? "on" : "off", privacy: .public)")
                self.isPrecise = precise
            }
            if status != .notDetermined {
                self.decisionWaiters.forEach { $0.resume() }
                self.decisionWaiters = []
            }
            // Chain straight into the Always prompt after While Using is granted.
            if status == .authorizedWhenInUse { self.manager.requestAlwaysAuthorization() }
            self.startMovementUpdatesIfAllowed()
            self.holdAlwaysSessionIfAllowed()
            if changed { self.onAuthorizationChange?() } // after the values above are updated
        }
    }

    /// Calls `onMove` whenever the phone moves about 500 m or more (at most every ~5 min). iOS
    /// relaunches the app in the background for these, even after it was force-quit, so call this
    /// on every launch. Uses cell and Wi-Fi, not GPS: little battery and no blue location pill.
    /// If Always isn't granted yet, it starts as soon as it is.
    func watchMovement(_ onMove: @escaping (CLLocation) -> Void) {
        self.onMove = onMove
        startMovementUpdatesIfAllowed()
    }

    private func startMovementUpdatesIfAllowed() {
        guard onMove != nil, authorization == .authorizedAlways,
              CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.startMonitoringSignificantLocationChanges()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.onMove?(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Log.app.error("Location updates failed: \(error.localizedDescription, privacy: .public)")
    }

    /// First fix with accuracy of `maxAccuracy` meters or better, within `timeout` seconds.
    func currentLocation(maxAccuracy: Double = 100, timeout: Double = 15) async throws -> CLLocation {
        guard authorization == .authorizedAlways || authorization == .authorizedWhenInUse else {
            throw LocationError.notAuthorized
        }
        return try await withThrowingTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                for try await update in CLLocationUpdate.liveUpdates() {
                    // Skip a cached fix: Core Location may hand out an old one first.
                    if let loc = update.location, loc.horizontalAccuracy >= 0,
                       loc.horizontalAccuracy <= maxAccuracy, -loc.timestamp.timeIntervalSinceNow <= 15 {
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
