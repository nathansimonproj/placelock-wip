import FamilyControls
import Foundation
import ManagedSettings

/// What the user chose to block.
/// - Real Screen Time build: `selection` from Apple's picker (opaque tokens, no app names).
/// - Simulated build: `simulatedApps`, names picked from a stand-in list.
struct BlockList: Codable {
    var selection = FamilyActivitySelection()
    var simulatedApps: [String] = []
    /// Removed apps that stay blocked until their date (24 h after removal). See `BlockRules`.
    var pendingRemovals = PendingRemovals()

    struct PendingRemovals: Codable {
        var simulated: [String: Date] = [:]
        var apps: [ApplicationToken: Date] = [:]
        var categories: [ActivityCategoryToken: Date] = [:]
        var webDomains: [WebDomainToken: Date] = [:]

        var isEmpty: Bool { simulated.isEmpty && apps.isEmpty && categories.isEmpty && webDomains.isEmpty }

        /// The soonest removal date, if any.
        var next: Date? {
            (Array(simulated.values) + Array(apps.values) + Array(categories.values) + Array(webDomains.values)).min()
        }
    }

    var isEmpty: Bool {
        ShieldManager.isSimulated
            ? simulatedApps.isEmpty
            : selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty
                && selection.webDomainTokens.isEmpty
    }

    /// e.g. "3 apps, 1 category" or "Instagram, TikTok".
    var summary: String {
        if ShieldManager.isSimulated { return simulatedApps.joined(separator: ", ") }
        var parts: [String] = []
        let s = selection
        if !s.applicationTokens.isEmpty { parts.append("\(s.applicationTokens.count) apps") }
        if !s.categoryTokens.isEmpty { parts.append("\(s.categoryTokens.count) categories") }
        if !s.webDomainTokens.isEmpty { parts.append("\(s.webDomainTokens.count) websites") }
        return parts.joined(separator: ", ")
    }
}

// Hand-written so block lists saved before `pendingRemovals` existed still load
// (synthesized decoding would fail on the missing key and reset the list to empty).
extension BlockList {
    private enum CodingKeys: String, CodingKey { case selection, simulatedApps, pendingRemovals }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selection = try c.decodeIfPresent(FamilyActivitySelection.self, forKey: .selection) ?? FamilyActivitySelection()
        simulatedApps = try c.decodeIfPresent([String].self, forKey: .simulatedApps) ?? []
        pendingRemovals = try c.decodeIfPresent(PendingRemovals.self, forKey: .pendingRemovals) ?? PendingRemovals()
    }
}

/// Stand-in for Apple's app picker while blocking is simulated.
enum SimulatedApps {
    static let all: [(name: String, symbol: String)] = [
        ("Instagram", "camera"), ("TikTok", "music.note"), ("YouTube", "play.rectangle"),
        ("X", "xmark"), ("Reddit", "bubble.left.and.bubble.right"), ("Snapchat", "message"),
        ("Facebook", "person.2"), ("Netflix", "tv"), ("Discord", "headphones"),
        ("Twitch", "gamecontroller"), ("Pinterest", "pin"), ("BeReal", "camera.on.rectangle"),
        ("Safari", "safari"), ("Messages", "message.fill"), ("Mail", "envelope"),
    ]

    static func symbol(for name: String) -> String {
        all.first { $0.name == name }?.symbol ?? "app"
    }
}
