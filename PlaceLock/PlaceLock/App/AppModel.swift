import CoreLocation
import Foundation
import ManagedSettings
import UserNotifications

/// App state + the lock/unlock rules. One shared instance so background relaunches see the same state.
/// Blocking goes through `ShieldManager` (real Screen Time on a paid team, simulated otherwise).
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // The decisions themselves live in Models/Rules.swift (LockRules, PlaceRules, BlockRules) as
    // pure functions with unit tests. This class gathers their inputs and applies the results.

    @Published var places: [Place] = [] {
        didSet {
            save(places, key: Keys.places)
            if !applyingRemote { SyncEngine.shared.placesChanged(old: oldValue, new: places) }
            Task { await GeofenceMonitor.shared.sync(places); await reconcile() }
        }
    }
    /// True while taking places from the server, so they aren't queued to upload again.
    private var applyingRemote = false
    @Published var blockList = BlockList() {
        didSet {
            // Removing an app waits 24 h (after setup): it stays blocked until then.
            // A @Published property's didSet runs again on reassignment, so reassign once with the
            // flag set; that inner pass does the saving below.
            if !bypassRemovalHold {
                bypassRemovalHold = true
                blockList = BlockRules.holdingRemovals(old: oldValue, new: blockList,
                                                       delayed: !inSetupWindow, now: .now)
                bypassRemovalHold = false
                return
            }
            save(blockList, key: Keys.blockList)
            scheduleNextActivation()
            if session == nil { ShieldManager.lock(blockList) } // newly picked apps get blocked right away
        }
    }
    @Published private(set) var session: UnlockSession? { didSet { save(session, key: Keys.session) } }
    /// Places you're at but chose to stay locked at ("Lock until I leave").
    /// A place leaves this set once iOS sees you leave it.
    @Published private(set) var pausedPlaceIDs: Set<UUID> = [] { didSet { save(pausedPlaceIDs, key: Keys.paused) } }
    /// Allowlist names still waiting for a location (e.g. "Home"). Tapping one opens Add place.
    @Published var placeSlots: [String] = [] { didSet { save(placeSlots, key: Keys.slots) } }
    @Published var message: String?
    /// Until this time (first 24 h after install) place changes apply instantly, so initial
    /// setup has no wait. "Finish setup" ends it early.
    @Published private(set) var setupEndsAt: Date = .distantPast { didSet { save(setupEndsAt, key: Keys.setupEnds) } }

    private var activationTimer: Task<Void, Never>?
    private var bypassRemovalHold = false

    /// Dev tool: pretend you're at a place (or nowhere) instead of using real geofences.
    /// nil means real location. Kept in memory only, so a relaunch goes back to real.
    @Published var simulatedSpot: SimulatedSpot? {
        didSet {
            guard simulatedSpot != oldValue else { return }
            Log.app.info("Simulated location: \(String(describing: self.simulatedSpot), privacy: .public)")
            Task { await reconcile() }
        }
    }

    enum SimulatedSpot: Hashable {
        case place(UUID)
        case elsewhere
    }

    let location = LocationService()

    private var reconcileTask: Task<Void, Never>?

    private enum Keys {
        static let places = "places", session = "session", blockList = "blockList", paused = "pausedPlaces"
        static let slots = "placeSlots", seeded = "seededDefaultPlaces", setupEnds = "setupEndsAt"
    }

    private init() {
        places = load([Place].self, key: Keys.places) ?? []
        blockList = load(BlockList.self, key: Keys.blockList) ?? BlockList()
        session = load(UnlockSession.self, key: Keys.session)
        pausedPlaceIDs = load(Set<UUID>.self, key: Keys.paused) ?? []
        placeSlots = load([String].self, key: Keys.slots) ?? []
        if let saved = load(Date.self, key: Keys.setupEnds) {
            setupEndsAt = saved
        } else {
            setupEndsAt = .now.addingTimeInterval(PlaceRules.changeDelay) // first launch (or first with this feature)
            save(setupEndsAt, key: Keys.setupEnds)
        }
        seedDefaultPlacesOnce()
    }

    /// Adds the starter allowlist (`DefaultPlaces`) one time per install, skipping any name
    /// you already have. Deleting a starter place later doesn't bring it back.
    private func seedDefaultPlacesOnce() {
        guard !UserDefaults.standard.bool(forKey: Keys.seeded) else { return }
        let have = Set(places.map { $0.name.lowercased() })
        let newPlaces = DefaultPlaces.places.filter { !have.contains($0.name.lowercased()) }
        let newSlots = DefaultPlaces.slots.filter { !have.contains($0.lowercased()) && !placeSlots.contains($0) }
        places += newPlaces // property observers don't run in init, so save explicitly
        placeSlots += newSlots
        save(places, key: Keys.places)
        save(placeSlots, key: Keys.slots)
        UserDefaults.standard.set(true, forKey: Keys.seeded)
        Log.app.info("Seeded \(newPlaces.count) places, \(newSlots.count) slots")
    }

    var activePlace: Place? {
        guard let session else { return nil }
        return places.first { $0.id == session.placeID }
    }

    var isUnlocked: Bool { session != nil }

    var inSetupWindow: Bool { Date.now < setupEndsAt }

    /// Ends the setup window now. From here on, new places and enlargements wait 24 h.
    func finishSetup() {
        setupEndsAt = .now
        Log.app.info("Setup window finished early")
        SyncEngine.shared.setupWindowChanged()
    }

    // MARK: Sync (see Sync/SyncEngine.swift)

    /// Places restored or edited on another device. Geofences and the lock state follow as usual.
    func applyRemotePlaces(_ newPlaces: [Place]) {
        applyingRemote = true
        places = newPlaces
        applyingRemote = false
        Log.app.info("Applied \(newPlaces.count) places from the server")
    }

    /// The account's setup window ended earlier (e.g. before a reinstall). Only ever shortens it.
    func adoptSetupEnd(_ date: Date) {
        guard date < setupEndsAt else { return }
        setupEndsAt = date
        Log.app.info("Setup window end restored from the server")
    }

    // MARK: Launch

    /// Runs on every launch, including background relaunches for geofence events.
    func startUp() async {
        Log.app.info("Launch: \(self.places.count) places, session=\(self.activePlace?.name ?? "none", privacy: .public)")
        await GeofenceMonitor.shared.start { await AppModel.shared.reconcile() }
        await GeofenceMonitor.shared.sync(places)
        await reconcile()
        SyncEngine.shared.start() // after the lock state is settled; sync never gates blocking
    }

    // MARK: Lock state

    /// Make the lock state match where iOS says you are. Apps are locked by default and unlock
    /// on their own while you're inside a saved place. Runs after every geofence event, on launch,
    /// when the app comes to the front, and when places change. Calls run one at a time.
    func reconcile() async {
        let previous = reconcileTask
        let task = Task { @MainActor in
            await previous?.value
            await self.reconcileNow()
        }
        reconcileTask = task
        await task.value
    }

    private func reconcileNow() async {
        applyDueChanges()
        defer { scheduleNextActivation() }

        let hasAlways = location.hasAlways
        var presence: [UUID: Presence] = [:]
        if hasAlways {
            if let simulated = simulatedPresence() {
                presence = simulated
            } else {
                presence = await GeofenceMonitor.shared.states().mapValues(Presence.init)
            }
        }
        let (action, paused) = LockRules.decide(.init(
            places: places, session: session, paused: pausedPlaceIDs, presence: presence,
            hasAlways: hasAlways, now: .now, checkSessionCap: simulatedSpot == nil))
        if paused != pausedPlaceIDs { pausedPlaceIDs = paused }

        switch action {
        case .stayLocked:
            ShieldManager.lock(blockList)
        case .stayUnlocked:
            break
        case .unlock(let id):
            if let place = places.first(where: { $0.id == id }) { unlock(at: place) }
        case .move(let from, let to):
            if let old = session { SyncEngine.shared.sessionEnded(old, reason: .moved) }
            let moved = UnlockSession(placeID: to, startedAt: .now)
            session = moved
            SyncEngine.shared.sessionStarted(moved)
            Log.app.info("Moved session from \(from.uuidString, privacy: .public) to \(to.uuidString, privacy: .public)")
        case .lock(let reason):
            // LockRules locks a running session for one of three reasons; name it for history.
            let end: SessionEnd = !hasAlways ? .lostAlways : (activePlace == nil ? .placeDeleted : .left)
            lockNow(reason: reason, end: end)
        case .recheck(let id):
            if let place = places.first(where: { $0.id == id }) { await recheck(place) }
        }
    }

    /// What the geofences would report if you stood at `simulatedSpot`. Nil when not simulating.
    private func simulatedPresence() -> [UUID: Presence]? {
        guard let simulatedSpot else { return nil }
        var here: CLLocation?
        if case .place(let id) = simulatedSpot { here = places.first { $0.id == id }?.location }
        return Dictionary(uniqueKeysWithValues: places.map { place in
            let inside = here.map { place.distanceOutside($0) <= 0 } ?? false
            return (place.id, inside ? .inside : .outside)
        })
    }

    private func unlock(at place: Place) {
        Log.app.info("Auto-unlock at \(place.name, privacy: .public)")
        ShieldManager.unlock()
        let started = UnlockSession(placeID: place.id, startedAt: .now)
        session = started
        SyncEngine.shared.sessionStarted(started)
        message = nil
        notify("Arrived at \(place.name), apps unblocked.")
    }

    /// Safety net for a missed exit event: after `maxSession`, confirm with a fresh GPS fix.
    private func recheck(_ place: Place) async {
        if let here = try? await location.currentLocation(),
           place.distanceOutside(here) <= here.horizontalAccuracy {
            Log.app.info("8 h recheck: still at \(place.name, privacy: .public)")
            session = session?.rechecked(at: .now) ?? UnlockSession(placeID: place.id, startedAt: .now)
        } else {
            pausedPlaceIDs.insert(place.id) // don't flip straight back to unlocked from a stale reading
            lockNow(reason: "Couldn't confirm you're still at \(place.name). Apps locked until you leave and come back.",
                    end: .recheckFailed)
        }
    }

    /// "Lock until I leave": lock now, and don't auto-unlock here again until you've left.
    func lockUntilLeave() {
        guard let place = activePlace else { return }
        pausedPlaceIDs.insert(place.id)
        lockNow(reason: nil, end: .lockUntilLeave)
        message = "Locked until you leave \(place.name)."
    }

    /// `end` is recorded in the synced history if a session was running.
    func lockNow(reason: String?, end: SessionEnd = .manual) {
        let wasUnlocked = session != nil
        Log.app.info("Lock (was unlocked: \(wasUnlocked)): \(reason ?? "manual", privacy: .public)")
        ShieldManager.lock(blockList)
        if let session { SyncEngine.shared.sessionEnded(session, reason: end) }
        session = nil
        if let reason {
            message = reason
            if wasUnlocked { notify(reason) }
        }
    }

    // MARK: Places (with the 24 h delay)

    /// Saves a new place, filling the slot of the same name if there is one.
    /// Outside the setup window it starts working 24 h from now.
    func addPlace(_ place: Place, fillingSlot slot: String?) {
        let place = PlaceRules.added(place, inSetup: inSetupWindow, now: .now)
        if let when = place.activeAfter {
            scheduleActivationNotice(id: place.id, at: when, text: "\(place.name) is now on your allowlist.")
        }
        if let slot { placeSlots.removeAll { $0 == slot } }
        places.append(place)
        Log.app.info("Added \(place.name, privacy: .public), active \(place.activeAfter?.description ?? "now", privacy: .public)")
    }

    /// Renames apply right away. A new circle applies right away only if it makes the place
    /// stricter (fits inside the old one), during setup, or while the place isn't active yet.
    /// Otherwise it waits 24 h and the current circle keeps working until then.
    func editPlace(_ id: UUID, name: String, address: String?, center: CLLocationCoordinate2D, radius: Double) {
        guard let i = places.firstIndex(where: { $0.id == id }) else { return }
        let (place, result) = PlaceRules.edited(places[i], name: name, address: address, center: center,
                                                radius: radius, inSetup: inSetupWindow, now: .now)
        switch result {
        case .unchangedArea: break
        case .appliedNow: cancelActivationNotice(id: id, change: true)
        case .pending(let when):
            scheduleActivationNotice(id: id, at: when, text: "\(name)'s new area is now active.", change: true)
        }
        places[i] = place
    }

    /// Turns on places and changes whose 24 h are up, and drops blocked apps whose removal is due.
    private func applyDueChanges() {
        if let updated = PlaceRules.applyingDue(places, now: .now) {
            Log.app.info("Applied due place changes")
            places = updated // didSet re-syncs geofences and reconciles again
        }
        if let updated = BlockRules.applyingDueRemovals(blockList, now: .now) {
            Log.app.info("Applied due app removals")
            bypassRemovalHold = true
            blockList = updated
            bypassRemovalHold = false
        }
    }

    /// "Keep blocked": cancel a pending removal. Pass the item whose removal to cancel.
    func keepBlocked(app name: String) { blockList.pendingRemovals.simulated[name] = nil }
    func keepBlocked(token: ApplicationToken) { blockList.pendingRemovals.apps[token] = nil }
    func keepBlocked(category: ActivityCategoryToken) { blockList.pendingRemovals.categories[category] = nil }
    func keepBlocked(webDomain: WebDomainToken) { blockList.pendingRemovals.webDomains[webDomain] = nil }

    /// While the app is running, wake up when the next pending place or change comes due.
    /// If it's suspended, the activation notice and the next launch or geofence event catch it.
    private func scheduleNextActivation() {
        activationTimer?.cancel()
        // Overdue items count too (wait 0 s): otherwise rescheduling just after something came due
        // would skip it until the next launch.
        let next = (places.flatMap { [$0.activeAfter, $0.pendingChange?.appliesAt] } + [blockList.pendingRemovals.next])
            .compactMap { $0 }.min()
        guard let next else { return }
        activationTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow) + 1))
            guard !Task.isCancelled else { return }
            await self?.reconcile()
        }
    }

    #if DEBUG
    /// Dev tool: make every waiting place and change take effect now.
    func skipDelays() {
        for place in places {
            cancelActivationNotice(id: place.id)
            cancelActivationNotice(id: place.id, change: true)
        }
        places = PlaceRules.skippingDelays(places)
        if let removed = BlockRules.applyingDueRemovals(blockList, now: .distantFuture) {
            bypassRemovalHold = true
            blockList = removed
            bypassRemovalHold = false
        }
        Log.app.info("Skipped all 24 h delays")
    }
    #endif

    func deleteSlots(at offsets: IndexSet) {
        placeSlots.remove(atOffsets: offsets)
    }

    func deletePlaces(at offsets: IndexSet) {
        for i in offsets {
            cancelActivationNotice(id: places[i].id)
            cancelActivationNotice(id: places[i].id, change: true)
        }
        places.remove(atOffsets: offsets) // reconcile locks if the active place was removed
    }

    // MARK: Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ text: String) {
        let content = UNMutableNotificationContent()
        content.title = "PlaceLock"
        content.body = text
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func activationNoticeID(_ id: UUID, change: Bool) -> String {
        "\(change ? "change" : "activate")-\(id.uuidString)"
    }

    /// A heads-up when a waiting place or change turns on.
    private func scheduleActivationNotice(id: UUID, at date: Date, text: String, change: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = "PlaceLock"
        content.body = text
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: activationNoticeID(id, change: change), content: content, trigger: trigger))
    }

    private func cancelActivationNotice(id: UUID, change: Bool = false) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [activationNoticeID(id, change: change)])
    }

    // MARK: Persistence (UserDefaults JSON is plenty for an MVP)

    private func save<T: Encodable>(_ value: T?, key: String) {
        guard let value else { UserDefaults.standard.removeObject(forKey: key); return }
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
