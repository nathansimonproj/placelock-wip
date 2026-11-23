import Foundation

/// How saved data is read back, so a damaged or older save never crashes the app or quietly
/// empties it. `AppModel` saves JSON in `UserDefaults`; this decides what to load from it.
///
/// Safe means: keep blocking, keep everything that still reads, and report what was lost so
/// the caller can log it and set the original bytes aside (`Storage.keepUnreadable`).
enum SavedData {
    enum Outcome<Value> {
        /// Nothing saved under the key (a first launch, or never set).
        case missing
        case loaded(Value)
        /// A list where some items couldn't be read. Holds the rest, in their saved order.
        case partial(Value, dropped: Int)
        /// Something is saved, but none of it could be read.
        case unreadable

        /// What to use: everything that read, or nil if nothing did.
        var value: Value? {
            switch self {
            case .loaded(let value), .partial(let value, _): value
            case .missing, .unreadable: nil
            }
        }

        /// True when some saved data couldn't be read.
        var lostSomething: Bool {
            switch self {
            case .partial, .unreadable: true
            case .missing, .loaded: false
            }
        }
    }

    /// One saved value. `stored` is what `UserDefaults.object(forKey:)` returned.
    static func decode<T: Decodable>(_ type: T.Type, from stored: Any?) -> Outcome<T> {
        guard let stored else { return .missing }
        guard let data = stored as? Data, let value = try? JSONDecoder().decode(type, from: data) else {
            return .unreadable
        }
        return .loaded(value)
    }

    /// A saved list. Items that can't be read are dropped one by one, so one bad place doesn't
    /// cost the others.
    static func decodeList<T: Decodable>(of type: T.Type, from stored: Any?) -> Outcome<[T]> {
        guard let stored else { return .missing }
        guard let data = stored as? Data, let items = try? JSONDecoder().decode([Lenient<T>].self, from: data) else {
            return .unreadable
        }
        let kept = items.compactMap(\.value)
        return kept.count == items.count ? .loaded(kept) : .partial(kept, dropped: items.count - kept.count)
    }

    /// When the first day's setup window (instant place changes) ends. Nothing saved means a
    /// first launch: 24 h from now. A saved date that can't be read was set on an earlier launch,
    /// so setup is treated as over: a damaged save must not reopen a day without delays.
    static func setupEnd(_ saved: Outcome<Date>, now: Date) -> Date {
        switch saved {
        case .missing: now.addingTimeInterval(PlaceRules.changeDelay)
        case .loaded(let date), .partial(let date, _): date
        case .unreadable: .distantPast
        }
    }

    /// Decodes as nil instead of failing, so the list around it still loads.
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?

        init(from decoder: Decoder) throws {
            value = try? decoder.singleValueContainer().decode(T.self)
        }
    }
}
