import Foundation

/// One stretch of being unlocked at a place. Logged when the visit ends, for Home's stats.
struct Visit: Codable, Hashable {
    var placeID: UUID
    var start: Date
    var end: Date

    /// How long history is kept.
    static let keep: TimeInterval = 14 * 24 * 3600

    static func trimmed(_ visits: [Visit], now: Date = .now) -> [Visit] {
        visits.filter { $0.end > now.addingTimeInterval(-keep) }
    }
}

extension AppModel {
    /// Finished visits plus the one running now (ending at `now`).
    func allVisits(now: Date = .now) -> [Visit] {
        guard let session else { return visits }
        return visits + [Visit(placeID: session.placeID, start: session.visitStartedAt, end: now)]
    }

    /// Seconds unlocked between `from` and `to`.
    func unlockedTime(from: Date, to: Date = .now) -> TimeInterval {
        allVisits(now: to).reduce(0) { sum, visit in
            sum + max(0, min(visit.end, to).timeIntervalSince(max(visit.start, from)))
        }
    }

    /// Visits that began today.
    var unlocksToday: Int {
        let today = Calendar.current.startOfDay(for: .now)
        return allVisits().filter { $0.start >= today }.count
    }

    /// When the current locked stretch began: the end of the last visit. Nil while unlocked,
    /// or before any visit has been logged.
    var lockedSince: Date? {
        isUnlocked ? nil : visits.last?.end
    }

    /// Share of today so far spent locked, 0...1.
    var lockedShareToday: Double {
        let today = Calendar.current.startOfDay(for: .now)
        let elapsed = Date.now.timeIntervalSince(today)
        guard elapsed > 0 else { return 1 }
        return max(0, 1 - unlockedTime(from: today) / elapsed)
    }

    /// Number of apps, categories and sites blocked.
    var blockedCount: Int {
        ShieldManager.isSimulated
            ? blockList.simulatedApps.count
            : blockList.selection.applicationTokens.count + blockList.selection.categoryTokens.count
                + blockList.selection.webDomainTokens.count
    }
}

extension TimeInterval {
    /// "2h 14m", "45m".
    var hoursMinutes: String {
        let minutes = Int(self / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
