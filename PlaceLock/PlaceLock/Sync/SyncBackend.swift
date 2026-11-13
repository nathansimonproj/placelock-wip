import Foundation
import Supabase

/// The server calls sync makes. `SupabaseBackend` is the real one; unit tests use a fake.
/// Errors pass through as the server sent them (`URLError` offline, `PostgrestError` from the
/// database), because `SyncEngine` decides what to retry from their type.
@MainActor
protocol SyncBackend: AnyObject {
    /// True if a signed-in session is saved on this phone.
    var hasStoredSession: Bool { get }
    /// The saved account's id, refreshing its token if needed. Throws `URLError` when offline,
    /// and any other error when the session can't be used any more.
    func storedUserID() async throws -> UUID
    func signInAnonymously() async throws -> UUID
    /// `places` rows written after `after` (every row when nil), oldest first.
    func places(syncedAfter after: Date?) async throws -> [PlaceRecord]
    func profile(of user: UUID) async throws -> ProfileRecord
    func updateProfile(_ profile: ProfileRecord, of user: UUID) async throws
    func upsert(places: [PlaceRecord]) async throws
    func upsert(sessions: [SessionRecord]) async throws
    /// Deletes the signed-in account and every row it owns (`delete_my_account()`).
    func deleteAccount() async throws
    /// Forgets the saved session on this phone. Never fails.
    func signOut() async
}

@MainActor
final class SupabaseBackend: SyncBackend {
    private let client: SupabaseClient

    /// Nil without a Supabase URL and key in Info.plist, which turns sync off.
    init?(info: [String: Any]) {
        guard let urlString = info["SupabaseURL"] as? String, let url = URL(string: urlString),
              let key = info["SupabaseKey"] as? String, !key.isEmpty else { return nil }
        client = SupabaseClient(supabaseURL: url, supabaseKey: key,
                                options: .init(auth: .init(emitLocalSessionAsInitialSession: true)))
    }

    var hasStoredSession: Bool { client.auth.currentSession != nil }

    func storedUserID() async throws -> UUID {
        try await client.auth.session.user.id // refreshes if expired
    }

    func signInAnonymously() async throws -> UUID {
        try await client.auth.signInAnonymously().user.id
    }

    func places(syncedAfter after: Date?) async throws -> [PlaceRecord] {
        var query = client.from("places").select()
        if let after { query = query.gt("synced_at", value: Self.iso(after)) }
        return try await query.order("synced_at").execute().value
    }

    func profile(of user: UUID) async throws -> ProfileRecord {
        try await client.from("profiles")
            .select("setup_ends_at,updated_at").eq("id", value: user.uuidString).single().execute().value
    }

    func updateProfile(_ profile: ProfileRecord, of user: UUID) async throws {
        try await client.from("profiles")
            .update(profile, returning: .minimal).eq("id", value: user.uuidString).execute()
    }

    func upsert(places: [PlaceRecord]) async throws {
        try await client.from("places").upsert(places, onConflict: "id", returning: .minimal).execute()
    }

    func upsert(sessions: [SessionRecord]) async throws {
        try await client.from("sessions").upsert(sessions, onConflict: "id", returning: .minimal).execute()
    }

    func deleteAccount() async throws {
        try await client.rpc("delete_my_account").execute()
    }

    func signOut() async {
        // Removes the local session first, then tells the server. The account may already be
        // gone, so a failed server call doesn't matter.
        try? await client.auth.signOut(scope: .local)
    }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}
