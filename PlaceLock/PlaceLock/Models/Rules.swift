import CoreLocation
import Foundation

// The app's decisions as pure functions: no GPS, no Screen Time, no UserDefaults.
// `AppModel` gathers the inputs and applies the results. Unit tests call these directly.

/// What iOS (or the location simulator) says about one place.
enum Presence: Equatable {
    case inside, outside, unknown
}

// MARK: - Lock / unlock

enum LockRules {
    /// Unlocks end after this long unless a fresh GPS fix confirms you're still there.
    static let maxSession: TimeInterval = 8 * 60 * 60

    struct Input {
        var places: [Place]
        var session: UnlockSession?
        var paused: Set<UUID>
        var presence: [UUID: Presence]
        var hasAlways: Bool
        var now: Date
        /// False while simulating, so the 8 h recheck doesn't ask real GPS.
        var checkSessionCap = true
    }

    enum Action: Equatable {
        /// Make sure the block is on (nothing changes otherwise).
        case stayLocked
        case stayUnlocked
        case unlock(at: UUID)
        /// Left the session's place while inside another allowed place: keep apps open there.
        case move(from: UUID, to: UUID)
        case lock(reason: String)
        /// Unlocked longer than `maxSession`: confirm with a fresh GPS fix.
        case recheck(UUID)
    }

    /// Apps are blocked by default and unblock while you're inside an active, non-paused place.
    /// Also returns the paused set with places you've left removed.
    static func decide(_ input: Input) -> (action: Action, paused: Set<UUID>) {
        // Without Always, iOS can't wake us when you leave, so nothing may stay unlocked.
        guard input.hasAlways else {
            return (input.session == nil ? .stayLocked : .lock(reason: "Location is no longer set to Always. Apps locked."),
                    input.paused)
        }

        let inside = Set(input.presence.filter { $0.value == .inside }.keys)
        let paused = input.paused.intersection(inside) // left a paused place, so it can unlock next time
        let unlockable = input.places.first {
            inside.contains($0.id) && $0.isActive(at: input.now) && !paused.contains($0.id)
        }

        guard let session = input.session else {
            return (unlockable.map { .unlock(at: $0.id) } ?? .stayLocked, paused)
        }
        guard let place = input.places.first(where: { $0.id == session.placeID }) else {
            return (.lock(reason: "That place was deleted. Apps locked."), paused)
        }
        // Only a definite "outside" ends the session. Unknown readings are ignored.
        if input.presence[place.id] == .outside {
            if let next = unlockable { return (.move(from: place.id, to: next.id), paused) }
            return (.lock(reason: "Left \(place.name), apps locked."), paused)
        }
        if input.checkSessionCap, input.now.timeIntervalSince(session.startedAt) > maxSession {
            return (.recheck(place.id), paused)
        }
        return (.stayUnlocked, paused)
    }
}

// MARK: - Places and the 24 h delay

enum PlaceRules {
    /// New places, and moves or enlargements of existing ones, wait this long before they count.
    static let changeDelay: TimeInterval = 24 * 60 * 60

    /// A new place: active right away during setup, otherwise 24 h from now.
    static func added(_ place: Place, inSetup: Bool, now: Date) -> Place {
        var place = place
        place.activeAfter = inSetup ? nil : now.addingTimeInterval(changeDelay)
        return place
    }

    enum EditResult: Equatable {
        case unchangedArea
        case appliedNow
        case pending(until: Date)
    }

    /// Renames apply right away. A new circle applies right away only if it fits inside the old
    /// one (stricter), during setup, or while the place isn't active yet. Otherwise it waits 24 h
    /// and the current circle keeps working until then.
    static func edited(_ place: Place, name: String, address: String?, center: CLLocationCoordinate2D,
                       radius: Double, inSetup: Bool, now: Date) -> (Place, EditResult) {
        var place = place
        place.name = name
        place.address = address
        let unchanged = place.latitude == center.latitude && place.longitude == center.longitude
            && place.radius == radius
        if unchanged { return (place, .unchangedArea) }
        if inSetup || !place.isActive(at: now) || place.contains(center: center, radius: radius) {
            place.latitude = center.latitude
            place.longitude = center.longitude
            place.radius = radius
            place.pendingChange = nil
            return (place, .appliedNow)
        }
        let when = now.addingTimeInterval(changeDelay)
        place.pendingChange = .init(latitude: center.latitude, longitude: center.longitude, radius: radius, appliesAt: when)
        return (place, .pending(until: when))
    }

    /// Turns on places and area changes whose time has come. Nil if nothing was due.
    static func applyingDue(_ places: [Place], now: Date) -> [Place]? {
        var updated = places
        var changed = false
        for i in updated.indices {
            if let when = updated[i].activeAfter, when <= now {
                updated[i].activeAfter = nil
                changed = true
            }
            if let change = updated[i].pendingChange, change.appliesAt <= now {
                updated[i].apply(change)
                changed = true
            }
        }
        return changed ? updated : nil
    }

    /// Debug: everything waiting takes effect now.
    static func skippingDelays(_ places: [Place]) -> [Place] {
        places.map { place in
            var place = place
            place.activeAfter = nil
            if let change = place.pendingChange { place.apply(change) }
            return place
        }
    }
}

private extension Place {
    mutating func apply(_ change: PendingChange) {
        latitude = change.latitude
        longitude = change.longitude
        radius = change.radius
        pendingChange = nil
    }
}

// MARK: - Blocked apps and the 24 h removal delay

enum BlockRules {
    static let removalDelay: TimeInterval = 24 * 60 * 60

    /// Called with the block list before and after an edit (swipe, picker). While `delayed`,
    /// anything removed stays blocked and gets a removal date 24 h out instead. Additions are
    /// always instant. Outside the delay, removals are instant and stale pending dates are dropped.
    static func holdingRemovals(old: BlockList, new: BlockList, delayed: Bool, now: Date) -> BlockList {
        var result = new
        var pending = new.pendingRemovals
        result.simulatedApps = hold(old: old.simulatedApps, new: new.simulatedApps,
                                    pending: &pending.simulated, delayed: delayed, now: now)
        result.selection.applicationTokens = hold(old: old.selection.applicationTokens, new: new.selection.applicationTokens,
                                                  pending: &pending.apps, delayed: delayed, now: now)
        result.selection.categoryTokens = hold(old: old.selection.categoryTokens, new: new.selection.categoryTokens,
                                               pending: &pending.categories, delayed: delayed, now: now)
        result.selection.webDomainTokens = hold(old: old.selection.webDomainTokens, new: new.selection.webDomainTokens,
                                                pending: &pending.webDomains, delayed: delayed, now: now)
        result.pendingRemovals = pending
        return result
    }

    /// Removes everything whose 24 h are up. Nil if nothing was due.
    static func applyingDueRemovals(_ list: BlockList, now: Date) -> BlockList? {
        var list = list
        var changed = false
        changed = drop(dueBy: now, from: &list.simulatedApps, pending: &list.pendingRemovals.simulated) || changed
        changed = drop(dueBy: now, from: &list.selection.applicationTokens, pending: &list.pendingRemovals.apps) || changed
        changed = drop(dueBy: now, from: &list.selection.categoryTokens, pending: &list.pendingRemovals.categories) || changed
        changed = drop(dueBy: now, from: &list.selection.webDomainTokens, pending: &list.pendingRemovals.webDomains) || changed
        return changed ? list : nil
    }

    // Set version (Screen Time tokens).
    static func hold<T: Hashable>(old: Set<T>, new: Set<T>, pending: inout [T: Date], delayed: Bool, now: Date) -> Set<T> {
        guard delayed else {
            pending = pending.filter { new.contains($0.key) }
            return new
        }
        let removed = old.subtracting(new)
        for item in removed where pending[item] == nil {
            pending[item] = now.addingTimeInterval(removalDelay)
        }
        let kept = new.union(removed)
        pending = pending.filter { kept.contains($0.key) }
        return kept
    }

    // Ordered version (simulated app names): kept items stay in their old order, additions go last.
    static func hold(old: [String], new: [String], pending: inout [String: Date], delayed: Bool, now: Date) -> [String] {
        let kept = hold(old: Set(old), new: Set(new), pending: &pending, delayed: delayed, now: now)
        return old.filter(kept.contains) + new.filter { !old.contains($0) && kept.contains($0) }
    }

    private static func drop<T: Hashable>(dueBy now: Date, from set: inout Set<T>, pending: inout [T: Date]) -> Bool {
        let due = Set(pending.filter { $0.value <= now }.keys)
        guard !due.isEmpty else { return false }
        set.subtract(due)
        pending = pending.filter { !due.contains($0.key) }
        return true
    }

    private static func drop(dueBy now: Date, from list: inout [String], pending: inout [String: Date]) -> Bool {
        let due = Set(pending.filter { $0.value <= now }.keys)
        guard !due.isEmpty else { return false }
        list.removeAll(where: due.contains)
        pending = pending.filter { !due.contains($0.key) }
        return true
    }
}
