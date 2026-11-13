import Foundation
import Network
import Supabase

/// Backs up places, the setup window and unlock history to Supabase, and restores them.
///
/// The phone decides blocking: nothing here is ever on the path to locking or unlocking, and
/// with no network (or no configuration) the app behaves exactly as it does without sync.
/// Local edits queue in a persisted `Outbox` and upload when online; newest edit wins (the
/// server enforces it too). Decisions live in `SyncRules`; this class does the I/O.
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    enum Status: Equatable {
        /// No Supabase URL/key in Info.plist, or running unit tests.
        case off
        case idle
        case syncing
        case synced(Date)
        case failed(String)
    }

    @Published private(set) var status: Status
    @Published private(set) var pendingCount = 0

    private let client: SupabaseClient?
    private var state: State { didSet { persist(); pendingCount = state.outbox.count } }
    private var running: Task<Void, Never>?
    private var needsAnotherPass = false
    private var failures = 0
    private var retryTask: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private var started = false

    /// Everything sync needs to remember across launches.
    private struct State: Codable {
        var outbox = Outbox()
        /// Server time of the newest row pulled. Nil until the first successful sync.
        var lastPull: Date?
        /// See `SyncRules.MergeInput.editedAt`.
        var editedAt: [UUID: Date] = [:]
    }

    private static let stateKey = "sync"

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let underTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !underTests,
           let urlString = info["SupabaseURL"] as? String, let url = URL(string: urlString),
           let key = info["SupabaseKey"] as? String, !key.isEmpty {
            client = SupabaseClient(supabaseURL: url, supabaseKey: key,
                                    options: .init(auth: .init(emitLocalSessionAsInitialSession: true)))
            status = .idle
        } else {
            client = nil
            status = .off
        }
        state = Storage.defaults.data(forKey: Self.stateKey)
            .flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
        pendingCount = state.outbox.count
    }

    var isEnabled: Bool { client != nil }

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

    // MARK: Running passes

    /// Runs a sync pass now, or right after the one in progress.
    func requestSync() {
        guard isEnabled else { return }
        if running != nil { needsAnotherPass = true; return }
        retryTask?.cancel()
        running = Task { [weak self] in
            await self?.runPasses()
            self?.running = nil
        }
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
        guard let client else { return }
        let userID = try await signedInUserID(client)
        try await pullPlaces(client)
        try await syncSetupWindow(client, userID: userID)
        try await flushOutbox(client)
    }

    // MARK: Steps

    /// The current account, creating an anonymous one on first use.
    private func signedInUserID(_ client: SupabaseClient) async throws -> UUID {
        if client.auth.currentSession != nil {
            do {
                return try await client.auth.session.user.id // refreshes if expired
            } catch let error as URLError {
                throw error // offline: keep the account, try again later
            } catch {
                // The stored session can't be refreshed (revoked or expired for good).
                Log.sync.error("Session unusable, starting a new account: \(String(describing: error), privacy: .public)")
                state.lastPull = nil // the new account starts empty: upload everything on its first sync
            }
        }
        let session = try await client.auth.signInAnonymously()
        Log.sync.info("Signed in anonymously as \(session.user.id.uuidString, privacy: .public)")
        return session.user.id
    }

    private func pullPlaces(_ client: SupabaseClient) async throws {
        var query = client.from("places").select()
        if let lastPull = state.lastPull { query = query.gt("synced_at", value: Self.iso(lastPull)) }
        let rows: [PlaceRecord] = try await query.order("synced_at").execute().value

        let isFirstSync = state.lastPull == nil
        let model = AppModel.shared
        let result = SyncRules.merge(.init(local: model.places, editedAt: state.editedAt, remote: rows,
                                           isFirstSync: isFirstSync, now: .now))
        state.editedAt = result.editedAt
        for upload in result.uploads { state.outbox.add(.place(upload)) }
        if let places = result.places { model.applyRemotePlaces(places) }
        // On the first sync, record that it happened even if the server had no rows yet.
        state.lastPull = rows.compactMap(\.syncedAt).max() ?? state.lastPull ?? .distantPast
        if !rows.isEmpty || !result.uploads.isEmpty {
            Log.sync.info("Pulled \(rows.count) places (first sync: \(isFirstSync)), queued \(result.uploads.count) uploads")
        }
    }

    /// The earliest setup-window end wins on both sides.
    private func syncSetupWindow(_ client: SupabaseClient, userID: UUID) async throws {
        let profile: ProfileRecord = try await client.from("profiles")
            .select("setup_ends_at,updated_at").eq("id", value: userID.uuidString).single().execute().value
        let local = AppModel.shared.setupEndsAt
        let merged = SyncRules.mergedSetupEnd(local: local, remote: profile.setupEndsAt)
        if merged < local { AppModel.shared.adoptSetupEnd(merged) }
        let serverIsCurrent = profile.setupEndsAt.map { abs($0.timeIntervalSince(merged)) < 1 } ?? false
        if !serverIsCurrent {
            try await client.from("profiles")
                .update(ProfileRecord(setupEndsAt: merged, updatedAt: max(.now, profile.updatedAt)), returning: .minimal)
                .eq("id", value: userID.uuidString).execute()
        }
    }

    private func flushOutbox(_ client: SupabaseClient) async throws {
        let places = state.outbox.places, sessions = state.outbox.sessions
        if !places.isEmpty {
            try await upload(places, to: "places", using: client) { .place($0) }
        }
        if !sessions.isEmpty {
            try await upload(sessions, to: "sessions", using: client) { .session($0) }
        }
    }

    /// Upserts a batch. If the server rejects it for good, retries row by row and drops only the
    /// rows that fail permanently, so one bad row can't block the queue.
    private func upload<R: Encodable>(_ records: [R], to table: String, using client: SupabaseClient,
                                      as change: (R) -> SyncChange) async throws {
        do {
            try await client.from(table).upsert(records, onConflict: "id", returning: .minimal).execute()
            state.outbox.remove(records.map(change))
            Log.sync.info("Uploaded \(records.count) \(table, privacy: .public)")
        } catch let error as PostgrestError where SyncRules.isPermanentFailure(postgresCode: error.code) {
            for record in records {
                do {
                    try await client.from(table).upsert([record], onConflict: "id", returning: .minimal).execute()
                } catch let error as PostgrestError where SyncRules.isPermanentFailure(postgresCode: error.code) {
                    Log.sync.error("Dropped a \(table, privacy: .public) row the server rejects: \(error.message, privacy: .public)")
                }
                state.outbox.remove([change(record)])
            }
        }
    }

    // MARK: Helpers

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private static func describe(_ error: Error) -> String {
        if error is URLError { return "Offline" }
        if let error = error as? PostgrestError { return error.message }
        if let error = error as? AuthError { return error.message }
        return error.localizedDescription
    }

    private func persist() {
        Storage.defaults.set(try? JSONEncoder().encode(state), forKey: Self.stateKey)
    }
}
