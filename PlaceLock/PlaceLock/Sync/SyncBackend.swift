import Foundation
import Supabase

/// The server calls sync makes. `SupabaseBackend` is the real one; unit tests use a fake.
/// Errors pass through as the server sent them (`URLError` offline, `PostgrestError` from the
/// database), because `SyncEngine` decides what to retry from their type.
/// One pull of `places` rows.
struct PlacePage {
    var rows: [PlaceRecord]
    /// The newest row's `synced_at` exactly as the server wrote it, to pass back as the next
    /// pull's cursor. Not a `Date`: Postgres keeps microseconds, and a `Date` round trip lost
    /// them, so `synced_at > cursor` matched the newest row again on every pass.
    var cursor: String?
}

@MainActor
protocol SyncBackend: AnyObject {
    /// True if a signed-in session is saved on this phone.
    var hasStoredSession: Bool { get }
    /// The saved account's id, refreshing its token if needed. Throws `URLError` when offline,
    /// and any other error when the session can't be used any more.
    func storedUserID() async throws -> UUID
    func signInAnonymously() async throws -> UUID
    /// `places` rows written after `cursor` (every row when nil), oldest first.
    func places(syncedAfter cursor: String?) async throws -> PlacePage
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

    func places(syncedAfter cursor: String?) async throws -> PlacePage {
        var query = client.from("places").select()
        if let cursor { query = query.gt("synced_at", value: cursor) }
        let response: PostgrestResponse<[PlaceRecord]> = try await query.order("synced_at").execute()
        return PlacePage(rows: response.value, cursor: Self.newestSyncedAt(in: response.data))
    }

    /// The last `synced_at` string in a JSON array of rows sorted by it, untouched.
    static func newestSyncedAt(in json: Data) -> String? {
        struct Stamp: Decodable {
            var syncedAt: String?
            enum CodingKeys: String, CodingKey { case syncedAt = "synced_at" }
        }
        return (try? JSONDecoder().decode([Stamp].self, from: json))?.compactMap(\.syncedAt).last
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

}
