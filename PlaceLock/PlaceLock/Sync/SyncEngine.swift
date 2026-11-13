import Foundation
import Network
import Supabase

/// What sync reads and changes on the phone. `AppModel` in the app, a fake in unit tests.
@MainActor
protocol SyncLocal: AnyObject {
    var places: [Place] { get }
    var setupEndsAt: Date { get }
    /// Places restored or edited on another device.
    func applyRemotePlaces(_ places: [Place])
    /// The account's setup window ended earlier. Only ever shortens it.
    func adoptSetupEnd(_ date: Date)
}

extension AppModel: SyncLocal {}

/// Backs up places, the setup window and unlock history to Supabase, and restores them.
///
/// The phone decides blocking: nothing here is ever on the path to locking or unlocking, and
/// with no network (or no configuration) the app behaves exactly as it does without sync.
/// Local edits queue in a persisted `Outbox` and upload when online; newest edit wins (the
/// server enforces it too). Decisions live in `SyncRules`, server calls in `SyncBackend`;
/// this class runs the passes.
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine(
        backend: isUnderTests ? nil : SupabaseBackend(info: Bundle.main.infoDictionary ?? [:]),
        local: { AppModel.shared }, // resolved late: AppModel and SyncEngine refer to each other
        defaults: Storage.defaults)

    private static var isUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    enum Status: Equatable {
        /// No Supabase URL/key in Info.plist, or running unit tests.
        case off
        /// The user deleted their account. Backup stays off until they turn it back on.
        case turnedOff
        case idle
        case syncing
        case synced(Date)
        case failed(String)
    }

    @Published private(set) var status: Status
    @Published private(set) var pendingCount = 0

    private let backend: (any SyncBackend)?
    private let localProvider: @MainActor () -> any SyncLocal
    private var local: any SyncLocal { localProvider() }
    private let defaults: UserDefaults
    private var state: State { didSet { persist(); pendingCount = state.outbox.count } }
    private var running: Task<Void, Never>?
    private var needsAnotherPass = false
    private var failures = 0
    private var retryTask: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private var started = false
    /// True while deleting the account, so no pass starts in the middle of it.
    private var deleting = false

    /// Everything sync needs to remember across launches.
    private struct State: Codable {
        var outbox = Outbox()
        /// Server time of the newest row pulled. Nil until the first successful sync.
        var lastPull: Date?
        /// See `SyncRules.MergeInput.editedAt`.
        var editedAt: [UUID: Date] = [:]
        /// When the user deleted their account. Backup stays off while set.
        /// Optional so state saved before this field existed still loads.
        var turnedOffAt: Date?
    }

    private static let stateKey = "sync"

    init(backend: (any SyncBackend)?, local: @escaping @MainActor () -> any SyncLocal, defaults: UserDefaults) {
        self.backend = backend
        self.localProvider = local
        self.defaults = defaults
        state = defaults.data(forKey: Self.stateKey)
            .flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
        status = backend == nil ? .off : state.turnedOffAt != nil ? .turnedOff : .idle
        pendingCount = state.outbox.count
    }

    /// Supabase is configured, so backup can run (it may still be turned off).
    var isAvailable: Bool { backend != nil }

    /// Backup is configured and not turned off.
    var isEnabled: Bool { backend != nil && state.turnedOffAt == nil }

    /// Call on every launch, including background relaunches.
    func start() {
        guard isEnabled, !started else { return }
        started = true
        pathMonitor.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in SyncEngine.shared.requestSync() }
        }
        pathMonitor.start(queue: .global(qos: .utility))
        requestSync()
    }

    // MARK: Local changes (called by AppModel)

    /// Queues uploads for an edit of the place list.
    func placesChanged(old: [Place], new: [Place]) {
        guard isEnabled else { return }
        let now = Date.now
        let records = SyncRules.placeChanges(old: old, new: new, now: now)
        guard !records.isEmpty else { return }
        for record in records {
            state.editedAt[record.id] = now
            state.outbox.add(.place(record))
        }
        requestSync()
    }

    func sessionStarted(_ session: UnlockSession) {
        enqueue(.session(SessionRecord(session, updatedAt: .now)))
    }

    func sessionEnded(_ session: UnlockSession, reason: SessionEnd) {
        let now = Date.now
        enqueue(.session(SessionRecord(session, endedAt: now, reason: reason, updatedAt: now)))
    }

    /// Something not in the outbox changed (the setup window). The next pass picks it up.
    func setupWindowChanged() { requestSync() }

    private func enqueue(_ change: SyncChange) {
        guard isEnabled else { return }
        state.outbox.add(change)
        requestSync()
    }

    // MARK: Account

    /// Deletes the account and everything backed up (places, history, profile), then turns
    /// backup off on this phone. Places and blocked apps stay on the phone. Throws if the server
    /// couldn't delete it; nothing changes on the phone then.
    func deleteAccount() async throws {
        guard let backend else { return }
        deleting = true
        defer { deleting = false }
        retryTask?.cancel()
        while let running { await running.value } // let a pass in flight finish first
        retryTask?.cancel() // a failed pass may have scheduled another retry
        if backend.hasStoredSession { // no session means no account was ever made
            try await backend.deleteAccount()
        }
        await backend.signOut()
        state = State(turnedOffAt: .now)
        failures = 0
        status = .turnedOff
        Log.sync.info("Account deleted, backup turned off")
    }

    /// Turns backup back on after the account was deleted. A new account starts, and this
    /// phone's places upload to it.
    func turnBackOn() {
        guard backend != nil, state.turnedOffAt != nil else { return }
        state.turnedOffAt = nil
        status = .idle
        Log.sync.info("Backup turned back on")
        start()
        requestSync() // in case start() already ran this launch
    }

    // MARK: Running passes

    /// Runs a sync pass now, or right after the one in progress.
    func requestSync() {
        guard isEnabled, !deleting else { return }
        if running != nil { needsAnotherPass = true; return }
        retryTask?.cancel()
        running = Task { [weak self] in
            await self?.runPasses()
            self?.running = nil
        }
    }

    /// Waits until no pass is running. A retry scheduled after a failure doesn't count.
    func waitUntilIdle() async {
        while let running { await running.value }
    }

    private func runPasses() async {
        repeat {
            needsAnotherPass = false
            status = .syncing
            do {
                try await syncOnce()
                failures = 0
                status = .synced(.now)
            } catch {
                failures += 1
                let delay = SyncRules.retryDelay(afterFailures: failures)
                status = .failed(Self.describe(error))
                Log.sync.error("Sync failed (\(self.failures)x, retry in \(Int(delay)) s): \(String(describing: error), privacy: .public)")
                retryTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    self?.requestSync()
                }
                return
            }
        } while needsAnotherPass
    }

    /// Pull, merge, then push. Pulling first means a fresh install restores before it uploads.
    private func syncOnce() async throws {
        guard let backend else { return }
        let userID = try await signedInUserID(backend)
        try await pullPlaces(backend)
        try await syncSetupWindow(backend, userID: userID)
        try await flushOutbox(backend)
    }

    // MARK: Steps

    /// The current account, creating an anonymous one on first use.
    private func signedInUserID(_ backend: any SyncBackend) async throws -> UUID {
        if backend.hasStoredSession {
            do {
                return try await backend.storedUserID()
            } catch let error as URLError {
                throw error // offline: keep the account, try again later
            } catch {
                // The stored session can't be refreshed (revoked or expired for good).
                Log.sync.error("Session unusable, starting a new account: \(String(describing: error), privacy: .public)")
                state.lastPull = nil // the new account starts empty: upload everything on its first sync
            }
        }
        let userID = try await backend.signInAnonymously()
        Log.sync.info("Signed in anonymously as \(userID.uuidString, privacy: .public)")
        return userID
    }

    private func pullPlaces(_ backend: any SyncBackend) async throws {
        let rows = try await backend.places(syncedAfter: state.lastPull)

        let isFirstSync = state.lastPull == nil
        let local = self.local
        let result = SyncRules.merge(.init(local: local.places, editedAt: state.editedAt, remote: rows,
                                           isFirstSync: isFirstSync, now: .now))
        state.editedAt = result.editedAt
        for upload in result.uploads { state.outbox.add(.place(upload)) }
        if let places = result.places { local.applyRemotePlaces(places) }
        // On the first sync, record that it happened even if the server had no rows yet.
        state.lastPull = rows.compactMap(\.syncedAt).max() ?? state.lastPull ?? .distantPast
        if !rows.isEmpty || !result.uploads.isEmpty {
            Log.sync.info("Pulled \(rows.count) places (first sync: \(isFirstSync)), queued \(result.uploads.count) uploads")
        }
    }

    /// The earliest setup-window end wins on both sides.
    private func syncSetupWindow(_ backend: any SyncBackend, userID: UUID) async throws {
        let profile = try await backend.profile(of: userID)
        let local = self.local
        let localEnd = local.setupEndsAt
        let merged = SyncRules.mergedSetupEnd(local: localEnd, remote: profile.setupEndsAt)
        if merged < localEnd { local.adoptSetupEnd(merged) }
        let serverIsCurrent = profile.setupEndsAt.map { abs($0.timeIntervalSince(merged)) < 1 } ?? false
        if !serverIsCurrent {
            try await backend.updateProfile(ProfileRecord(setupEndsAt: merged, updatedAt: max(.now, profile.updatedAt)),
                                            of: userID)
        }
    }

    private func flushOutbox(_ backend: any SyncBackend) async throws {
        let places = state.outbox.places, sessions = state.outbox.sessions
        if !places.isEmpty {
            try await upload(places, table: "places", as: { .place($0) }) { try await backend.upsert(places: $0) }
        }
        if !sessions.isEmpty {
            try await upload(sessions, table: "sessions", as: { .session($0) }) { try await backend.upsert(sessions: $0) }
        }
    }

    /// Upserts a batch. If the server rejects it for good, retries row by row and drops only the
    /// rows that fail permanently, so one bad row can't block the queue.
    private func upload<R>(_ records: [R], table: String, as change: (R) -> SyncChange,
                           send: ([R]) async throws -> Void) async throws {
        do {
            try await send(records)
            state.outbox.remove(records.map(change))
            Log.sync.info("Uploaded \(records.count) \(table, privacy: .public)")
        } catch let error as PostgrestError where SyncRules.isPermanentFailure(postgresCode: error.code) {
            for record in records {
                do {
                    try await send([record])
                } catch let error as PostgrestError where SyncRules.isPermanentFailure(postgresCode: error.code) {
                    Log.sync.error("Dropped a \(table, privacy: .public) row the server rejects: \(error.message, privacy: .public)")
                }
                state.outbox.remove([change(record)])
            }
        }
    }

    // MARK: Helpers

    static func describe(_ error: Error) -> String {
        if error is URLError { return "Offline" }
        if let error = error as? PostgrestError { return error.message }
        if let error = error as? AuthError { return error.message }
        return error.localizedDescription
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(state), forKey: Self.stateKey)
    }
}
