import Foundation

/// What VoiceOver reads where the screen shows a short form: "23 h" becomes "23 hours",
/// "2h 14m" becomes "2 hours, 14 minutes" and "150 m" becomes "150 meters".
enum SpokenRules {
    /// "2 hours, 14 minutes", "1 hour", "45 minutes", "0 minutes". Whole minutes, rounded down
    /// like `hoursMinutes`.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return count(rest, "minute") }
        if rest == 0 { return count(hours, "hour") }
        return "\(count(hours, "hour")), \(count(rest, "minute"))"
    }

    /// Time left until `date`: "23 hours, 4 minutes", or "now" in the last minute, the same
    /// moment `shortTimeLeft` says "now".
    static func timeLeft(until date: Date, now: Date = .now) -> String {
        let seconds = date.timeIntervalSince(now)
        return seconds <= 60 ? "now" : duration(seconds)
    }

    /// A place's radius: "150 meters".
    static func meters(_ radius: Double) -> String {
        count(Int(radius), "meter")
    }

    /// The big lock on Home: whether apps are blocked right now.
    static func lock(unlocked: Bool, nothingBlocked: Bool) -> String {
        if unlocked { return "Apps unblocked" }
        return nothingBlocked ? "No apps blocked yet" : "Apps blocked"
    }

    private static func count(_ n: Int, _ unit: String) -> String {
        "\(n) \(unit)\(n == 1 ? "" : "s")"
    }
}
