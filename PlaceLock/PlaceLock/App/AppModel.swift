import CoreLocation
import FamilyControls
import Foundation
import ManagedSettings
import UIKit
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
            shareAllowedPlaces()
            if !applyingRemote { SyncEngine.shared.placesChanged(old: oldValue, new: places) }
            Task { await reconcile() } // reconcile syncs the watched circles first
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
    @Published private(set) var session: UnlockSession? {
        didSet {
            save(session, key: Keys.session)
            // A visit ended (left, locked by hand, or moved to another place): log it for Home's stats.
            if let old = oldValue, old.id != session?.id {
                visits = Visit.trimmed(visits + [Visit(placeID: old.placeID, start: old.visitStartedAt, end: .now)])
            }
            if oldValue?.placeID != session?.placeID { lastEstimateAttempt = .distantPast } // re-estimate now
        }
    }
    /// The block screen's "Estimated @" (`refreshEstimate` in Location/Estimate.swift).
    var estimateTask: Task<Void, Never>?
    var lastEstimateAttempt = Date.distantPast
    /// The location from the latest significant-change wake (`watchMovement`).
    var lastMove: CLLocation?
    /// The last Apple Maps name looked up, so standing still doesn't ask Apple again.
    var lastGeocode: (location: CLLocation, name: String?)?
    /// Finished unlock visits from the last two weeks, oldest first. On this phone only.
    @Published private(set) var visits: [Visit] = [] { didSet { save(visits, key: Keys.visits) } }
    /// Allowlist names still waiting for a location (e.g. "Home"). Tapping one opens Add place.
    @Published var placeSlots: [String] = [] { didSet { save(placeSlots, key: Keys.slots) } }
    @Published var message: String?
    /// Until this time (first 24 h after install) place changes apply instantly, so initial
    /// setup has no wait. "Finish setup" ends it early.
    @Published private(set) var setupEndsAt: Date = .distantPast { didSet { save(setupEndsAt, key: Keys.setupEnds) } }
    /// Whether PlaceLock may block apps. Screen Time access can be turned off in Settings at any
    /// time, which silently removes every block, so this is checked on every reconcile.
    @Published private(set) var screenTimeAccess: ScreenTimeAccess = .notYet {
        didSet { Storage.defaults.set(screenTimeAccess.rawValue, forKey: Keys.screenTime) }
    }

    enum ScreenTimeAccess: String {
        case approved
        /// Never granted on this install.
        case notYet
        /// Granted before, then turned off in Settings.
        case turnedOff
    }

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
    /// True once `startWatchingPlaces` ran. Until then nothing touches CLMonitor's circles, since
    /// watching places makes iOS show the location prompt.
    private var watchingPlaces = false
    private var didStart = false

    private enum Keys {
        static let places = "places", session = "session", blockList = "blockList", paused = "pausedPlaces"
        static let slots = "placeSlots", seeded = "seededDefaultPlaces", setupEnds = "setupEndsAt"
        static let screenTime = "screenTimeAccess", onboarded = "onboarded", visits = "visits"
    }

    /// First-run setup (`OnboardingView`) is done or skipped.
    @Published private(set) var hasOnboarded: Bool

    private init() {
        if Storage.defaults.object(forKey: Keys.onboarded) == nil {
            // First launch with this flag. Installs from before first-run setup existed were set
            // up by hand: they're the ones that already seeded starter places. Decided only once,
            // since a new install seeds on its first launch too.
            hasOnboarded = Storage.defaults.bool(forKey: Keys.seeded)
            Storage.defaults.set(hasOnboarded, forKey: Keys.onboarded)
        } else {
            hasOnboarded = Storage.defaults.bool(forKey: Keys.onboarded)
        }
        // Saved values go straight into the @Published storage. Assigning them normally runs
        // didSet even here in init (it does for property wrappers), and those observers treat a
        // load as an edit: `places` queued every place for upload as "edited now" on each launch,
        // and `blockList` blocked apps because `session` wasn't loaded yet.
        _places = Published(initialValue: load([Place].self, key: Keys.places) ?? [])
        _blockList = Published(initialValue: load(BlockList.self, key: Keys.blockList) ?? BlockList())
        if !ShieldManager.isSimulated, let cleaned = blockList.droppingSimulatedApps() {
            _blockList = Published(initialValue: cleaned)
            save(cleaned, key: Keys.blockList)
        }
        _session = Published(initialValue: load(UnlockSession.self, key: Keys.session))
        _visits = Published(initialValue: load([Visit].self, key: Keys.visits) ?? [])
        #if DEBUG
        // Launch with `-demoHistory YES` to fill today with two sample visits (for screenshots).
        if UserDefaults.standard.bool(forKey: "demoHistory"), visits.isEmpty, places.count >= 2 {
            let today = Calendar.current.startOfDay(for: .now)
            visits = [
                Visit(placeID: places[0].id, start: today.addingTimeInterval(7.5 * 3600), end: today.addingTimeInterval(8.75 * 3600)),
                Visit(placeID: places[1].id, start: today.addingTimeInterval(12.2 * 3600), end: today.addingTimeInterval(13.1 * 3600)),
            ].filter { $0.end < .now }
        }
        #endif
        Storage.defaults.removeObject(forKey: Keys.paused) // "Lock until I leave" removed 2026-11-22
        _placeSlots = Published(initialValue: load([String].self, key: Keys.slots) ?? [])
        if let saved = load(Date.self, key: Keys.setupEnds) {
            _setupEndsAt = Published(initialValue: saved)
        } else {
            _setupEndsAt = Published(initialValue: .now.addingTimeInterval(PlaceRules.changeDelay)) // first launch (or first with this feature)
            save(setupEndsAt, key: Keys.setupEnds)
        }
        // A saved "approved" that no longer holds is left for `refreshScreenTimeAccess` to catch,
        // so it can warn that access was turned off.
        let savedAccess = Storage.defaults.string(forKey: Keys.screenTime).flatMap(ScreenTimeAccess.init)
        _screenTimeAccess = Published(initialValue: ShieldManager.isAuthorized ? .approved : (savedAccess ?? .notYet))
        seedDefaultPlacesOnce()
        // The loads above skip the observers, so share what the extensions need explicitly.
        shareAllowedPlaces()
        // Losing Always or Precise while the app is running locks right away, not at the next wake.
        location.onAuthorizationChange = { [weak self] in
            Task { await self?.reconcileWhileAwake() }
        }
    }

    /// The block screen lists where apps unblock. Only places that work right now count.
    private func shareAllowedPlaces() {
        SharedStore.allowedPlaceNames = places.filter { $0.isActive() }.map(\.name)
    }

    /// Adds the starter allowlist (`DefaultPlaces`) one time per install, skipping any name
    /// you already have. Deleting a starter place later doesn't bring it back.
    private func seedDefaultPlacesOnce() {
        guard !Storage.defaults.bool(forKey: Keys.seeded) else { return }
        let have = Set(places.map { $0.name.lowercased() })
        let newPlaces = DefaultPlaces.places.filter { !have.contains($0.name.lowercased()) }
        let newSlots = DefaultPlaces.slots.filter { !have.contains($0.lowercased()) && !placeSlots.contains($0) }
        // Observers do run here (this is a method, even though init calls it). Seeded places
        // aren't the user's edits, so don't queue them for sync: the first sync uploads them,
        // or drops them when the account already has places with these names (a reinstall
        // that kept its Keychain sign-in), instead of making duplicates.
        applyingRemote = true
        places += newPlaces
        applyingRemote = false
        placeSlots += newSlots
        save(places, key: Keys.places)
        save(placeSlots, key: Keys.slots)
        Storage.defaults.set(true, forKey: Keys.seeded)
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
        guard !didStart else { return }
        didStart = true
        Log.app.notice("Launch: \(self.places.count) places, session=\(self.activePlace?.name ?? "none", privacy: .public)")
        ShieldManager.stopLegacySessionCap()
        if location.authorization == .notDetermined {
            // Watching places makes iOS show the location prompt right away. On a new install,
            // wait until first-run setup has explained why and the user has answered it.
            Log.app.info("Waiting for the location prompt before watching places")
            Task {
                await location.waitForDecision()
                await startWatchingPlaces()
                await reconcile()
            }
        } else {
            await startWatchingPlaces()
        }
        await reconcile()
        SyncEngine.shared.start() // after the lock state is settled; sync never gates blocking
    }

    private func startWatchingPlaces() async {
        await GeofenceMonitor.shared.start { await AppModel.shared.reconcileWhileAwake() }
        watchingPlaces = true // the caller's reconcile syncs the circles
        startWatchingMovement()
    }

    /// Backstop for the geofences: iOS wakes the app every time you move about 500 m, even if it
    /// was force-quit, and the app re-reads iOS's state for every place (and refreshes the block
    /// screen's "Estimated @"). This catches a state change iOS recorded but didn't deliver. It
    /// doesn't catch an exit iOS hasn't noticed yet: the geofences still decide.
    private func startWatchingMovement() {
        location.watchMovement { [weak self] here in
            guard let self else { return }
            self.lastMove = here
            self.lastEstimateAttempt = .distantPast // estimate again right away
            Task {
                await self.logMove(here)
                await self.reconcileWhileAwake()
            }
        }
    }

    /// Logs a significant-change fix against the running session's place. Changes nothing: it's
    /// data for deciding whether iOS ever misses an exit (Roadmap, 2026-11-22).
    private func logMove(_ here: CLLocation) async {
        let fix = "±\(Int(here.horizontalAccuracy)) m, \(Int(-here.timestamp.timeIntervalSinceNow)) s old"
        guard let place = activePlace else {
            Log.app.notice("Moved (significant change, \(fix, privacy: .public))")
            return
        }
        let reading = await GeofenceMonitor.shared.states(for: [place])[place.id].map(Presence.init)
        let edge = place.distanceOutside(here)
        Log.app.notice("Moved (significant change, \(fix, privacy: .public)); session \(place.name, privacy: .private) reads \(reading.map { "\($0)" } ?? "nothing", privacy: .public), fix \(Int(abs(edge))) m \(edge > 0 ? "outside" : "inside", privacy: .public) its edge")
    }

    /// For wakes iOS gives the app in the background (a geofence or movement event): asks for a
    /// few extra seconds so the unlock or lock finishes before iOS suspends the app again.
    func reconcileWhileAwake() async {
        let task = UIApplication.shared.beginBackgroundTask(withName: "reconcile")
        await reconcile()
        if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
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
        await clearOldNotices() // before this pass sends its own
        await refreshScreenTimeAccess()
        applyDueChanges()
        // Every states read follows a sync of the same list, and passes run one at a time, so syncs
        // never overlap. A sync with nothing to change is one read of the monitor's identifiers.
        let watched = places
        if watchingPlaces { await GeofenceMonitor.shared.sync(watched) }
        defer {
            scheduleNextActivation()
            refreshEstimate()
        }

        // Without Precise Location iOS stops watching places, like losing Always: lock.
        let hasAlways = location.canWatchPlaces
        var presence: [UUID: Presence] = [:]
        if hasAlways {
            if let simulated = simulatedPresence() {
                presence = simulated
            } else {
                presence = await GeofenceMonitor.shared.states(for: watched).mapValues(Presence.init)
            }
        }
        let action = LockRules.decide(.init(
            places: places, session: session, presence: presence, hasAlways: hasAlways, now: .now))

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
            Log.app.notice("Moved session from \(from.uuidString, privacy: .public) to \(to.uuidString, privacy: .public)")
        case .lock(let reason):
            // LockRules locks a running session for one of three reasons; name it for history.
            let end: SessionEnd = !hasAlways ? .lostAlways : (activePlace == nil ? .placeDeleted : .left)
            lockNow(reason: reason, end: end)
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
        Log.app.notice("Auto-unlock at \(place.name, privacy: .public)")
        ShieldManager.unlock()
        let started = UnlockSession(placeID: place.id, startedAt: .now)
        session = started
        SyncEngine.shared.sessionStarted(started)
        message = nil
        notify("At \(place.name), apps unblocked.")
    }

    // MARK: Screen Time access

    /// Re-reads whether PlaceLock may block apps and warns once if access was turned off.
    func refreshScreenTimeAccess() async {
        var approved = ShieldManager.isAuthorized
        if !approved, screenTimeAccess == .approved {
            // The status can read as not approved for a moment right after launch. Look again
            // before calling it turned off.
            try? await Task.sleep(for: .seconds(1))
            approved = ShieldManager.isAuthorized
        }
        let access: ScreenTimeAccess = approved ? .approved : (screenTimeAccess == .notYet ? .notYet : .turnedOff)
        guard access != screenTimeAccess else { return }
        if access == .turnedOff {
            Log.app.error("Screen Time access was turned off")
            notify("Screen Time access is off, so Spots can't block apps. Open Spots to turn it back on.",
                   id: Self.screenTimeNoticeID)
        } else {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.screenTimeNoticeID])
            Log.app.info("Screen Time access: \(access.rawValue, privacy: .public)")
        }
        screenTimeAccess = access
    }

    /// `end` is recorded in the synced history if a session was running.
    func lockNow(reason: String?, end: SessionEnd = .manual) {
        let wasUnlocked = session != nil
        Log.app.notice("Lock (was unlocked: \(wasUnlocked)): \(reason ?? "manual", privacy: .public)")
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
    /// What Apple's app picker returns, capped at iOS's limit of 50 of each kind.
    func setSelection(_ picked: FamilyActivitySelection) {
        var selection = picked
        selection.applicationTokens = BlockRules.capped(picked.applicationTokens)
        selection.categoryTokens = BlockRules.capped(picked.categoryTokens)
        selection.webDomainTokens = BlockRules.capped(picked.webDomainTokens)
        let trimmed = picked.applicationTokens.count + picked.categoryTokens.count + picked.webDomainTokens.count
            - selection.applicationTokens.count - selection.categoryTokens.count - selection.webDomainTokens.count
        if trimmed > 0 {
            Log.app.info("Picker selection over the limit: dropped \(trimmed)")
            message = "Kept 50 of each. iOS can't block more than that."
        }
        blockList.selection = selection
    }

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
        let next = (places.flatMap { [$0.activeAfter, $0.pendingChange?.appliesAt] }
                    + [blockList.pendingRemovals.next])
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

    /// Asked during first-run setup, where the reason is on screen. True if allowed.
    @discardableResult
    func requestNotificationPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func finishOnboarding() {
        hasOnboarded = true
        Storage.defaults.set(true, forKey: Keys.onboarded)
        Log.app.info("First-run setup finished")
    }

    /// Arrive and leave notices share one ID, so each replaces the last and at most one sits in
    /// Notification Center.
    private static let statusNoticeID = "status"
    /// "Screen Time access is off" needs action, so it stays until access is back.
    private static let screenTimeNoticeID = "screen-time-off"
    /// How long arrive/leave and allowlist notices stay in Notification Center.
    static let noticeLifetime: TimeInterval = 5 * 60

    private func notify(_ text: String, id: String = AppModel.statusNoticeID) {
        let content = UNMutableNotificationContent()
        content.title = "Spots"
        content.body = text
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Notices are temporary. iOS has no expiry date for notifications, so the app removes them
    /// itself: all of them once the app is open, and ones older than `noticeLifetime` whenever
    /// iOS wakes the app (every geofence event and every ~500 m move). The Screen Time warning stays.
    func clearOldNotices(all: Bool = false) async {
        let center = UNUserNotificationCenter.current()
        let stale = await center.deliveredNotifications()
            .filter { $0.request.identifier != Self.screenTimeNoticeID }
            .filter { all || -$0.date.timeIntervalSinceNow > Self.noticeLifetime }
            .map(\.request.identifier)
        guard !stale.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: stale)
        Log.app.info("Cleared \(stale.count) old notification(s)")
    }

    private func activationNoticeID(_ id: UUID, change: Bool) -> String {
        "\(change ? "change" : "activate")-\(id.uuidString)"
    }

    /// A heads-up when a waiting place or change turns on.
    private func scheduleActivationNotice(id: UUID, at date: Date, text: String, change: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = "Spots"
        content.body = text
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: activationNoticeID(id, change: change), content: content, trigger: trigger))
    }

    private func cancelActivationNotice(id: UUID, change: Bool = false) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [activationNoticeID(id, change: change)])
    }

    // MARK: Persistence (UserDefaults JSON is plenty for an MVP; App Group in Screen Time builds)

    private func save<T: Encodable>(_ value: T?, key: String) {
        guard let value else { Storage.defaults.removeObject(forKey: key); return }
        Storage.defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = Storage.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
