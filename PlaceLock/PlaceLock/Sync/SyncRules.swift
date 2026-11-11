import Foundation

// Sync decisions as pure functions, like Models/Rules.swift: no network, no UserDefaults.
// `SyncEngine` gathers inputs and applies results. Unit tests call these directly.

/// One queued upload. A newer change to the same row replaces the older one.
enum SyncChange: Codable, Equatable {
    case place(PlaceRecord)
    case session(SessionRecord)

    /// Changes with the same key are the same row.
    var key: String {
        switch self {
        case .place(let r): "place:\(r.id)"
        case .session(let r): "session:\(r.id)"
        }
    }

    var updatedAt: Date {
        switch self {
        case .place(let r): r.updatedAt
        case .session(let r): r.updatedAt
        }
    }
}

/// Local changes waiting to upload. Persisted, so nothing is lost offline or across relaunches.
struct Outbox: Codable, Equatable {
    private(set) var changes: [SyncChange] = []

    var isEmpty: Bool { changes.isEmpty }
    var count: Int { changes.count }

    /// Queues a change. If the same row is already queued, the newer version wins.
    mutating func add(_ change: SyncChange) {
        if let i = changes.firstIndex(where: { $0.key == change.key }) {
            if change.updatedAt >= changes[i].updatedAt { changes[i] = change }
        } else {
            changes.append(change)
        }
    }

    /// Places go before sessions, so a session's place always exists on the server first.
    var places: [PlaceRecord] {
        changes.compactMap { if case .place(let r) = $0 { r } else { nil } }
    }

    var sessions: [SessionRecord] {
        changes.compactMap { if case .session(let r) = $0 { r } else { nil } }
    }

    /// Drops changes that were uploaded (or rejected for good). A change edited again while
    /// its upload was in flight differs from what was sent, so it stays queued.
    mutating func remove(_ done: [SyncChange]) {
        changes.removeAll { done.contains($0) }
    }
}

enum SyncRules {
    /// Uploads for a local edit of the place list: changed or new places, plus tombstones for
    /// deleted ones. `now` becomes each row's `updatedAt`.
    static func placeChanges(old: [Place], new: [Place], now: Date) -> [PlaceRecord] {
        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newIDs = Set(new.map(\.id))
        let changed = new.filter { oldByID[$0.id] != $0 }.map { PlaceRecord($0, updatedAt: now) }
        let deleted = old.filter { !newIDs.contains($0.id) }.map { PlaceRecord($0, updatedAt: now, deletedAt: now) }
        return changed + deleted
    }

    struct MergeInput {
        var local: [Place]
        /// When each place was last edited on this phone (or last taken from the server).
        /// Missing = never edited since sync existed: seeded starter places and pre-sync places.
        var editedAt: [UUID: Date]
        /// Rows pulled from the server since the last pull (all rows on the first sync).
        var remote: [PlaceRecord]
        var isFirstSync: Bool
        var now: Date
    }

    struct MergeResult: Equatable {
        /// The new local list, or nil if nothing changed.
        var places: [Place]?
        var editedAt: [UUID: Date]
        /// Local places the server doesn't have yet (first sync only).
        var uploads: [PlaceRecord]
    }

    /// Newest edit wins, per place. On the first sync, local places the server doesn't have are
    /// uploaded, except never-edited ones whose name the server already has: those are starter
    /// places seeded again on a reinstall, and the restored copy replaces them.
    static func merge(_ input: MergeInput) -> MergeResult {
        var places = input.local
        var editedAt = input.editedAt
        var changed = false

        for row in input.remote {
            let localEdit = editedAt[row.id] ?? .distantPast
            guard row.updatedAt > localEdit else { continue } // ours is newer (or it's our own echo)
            editedAt[row.id] = row.updatedAt
            let index = places.firstIndex { $0.id == row.id }
            switch (row.place, index) {
            case (let remote?, let i?): if places[i] != remote { places[i] = remote; changed = true }
            case (let remote?, nil): places.append(remote); changed = true
            case (nil, let i?): places.remove(at: i); changed = true
            case (nil, nil): break
            }
        }

        var uploads: [PlaceRecord] = []
        if input.isFirstSync {
            let remoteIDs = Set(input.remote.map(\.id))
            let remoteNames = Set(input.remote.compactMap { $0.place?.name.lowercased() })
            var kept: [Place] = []
            for place in places {
                if remoteIDs.contains(place.id) { kept.append(place); continue }
                if input.editedAt[place.id] == nil, remoteNames.contains(place.name.lowercased()) {
                    changed = true // duplicate starter place; the restored one stays
                    continue
                }
                let when = input.editedAt[place.id] ?? input.now
                editedAt[place.id] = when
                uploads.append(PlaceRecord(place, updatedAt: when))
                kept.append(place)
            }
            places = kept
        }

        return MergeResult(places: changed ? places : nil, editedAt: editedAt, uploads: uploads)
    }

    /// The setup window is stricter when it ends sooner, so the earliest end wins. This keeps
    /// a reinstall from opening a fresh no-delay window.
    static func mergedSetupEnd(local: Date, remote: Date?) -> Date {
        min(local, remote ?? local)
    }

    /// Server errors that will fail the same way on every retry (bad data, constraint, access):
    /// the change is dropped instead of blocking the queue. Postgres error codes: class 22 is
    /// data exceptions, 23 integrity constraints, 42501 insufficient privilege (row-level security).
    static func isPermanentFailure(postgresCode code: String?) -> Bool {
        guard let code else { return false }
        return code.hasPrefix("22") || code.hasPrefix("23") || code == "42501"
    }

    /// Wait before retrying after a failure: 5 s doubling up to 5 min.
    static func retryDelay(afterFailures n: Int) -> TimeInterval {
        min(5 * pow(2, Double(max(0, n - 1))), 300)
    }
}
