import Foundation

// MARK: - The About section: version and links

/// What the About section in the Settings tab shows. Rows whose value is missing or not usable
/// are hidden, so an unset link in `Brand` never shows up as a dead row.
enum AboutRules {
    struct Links: Equatable {
        var privacyPolicy: URL?
        /// "Contact support": an email if one is set, otherwise the support page.
        var support: URL?
    }

    static func links(privacyPolicy: String?, supportURL: String?, supportEmail: String?) -> Links {
        Links(privacyPolicy: webURL(privacyPolicy),
              support: mailURL(supportEmail) ?? webURL(supportURL))
    }

    /// An `https` address with a host, or nil.
    static func webURL(_ text: String?) -> URL? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let url = URL(string: text), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// `mailto:` for a plain address like name@example.com, or nil.
    static func mailURL(_ email: String?) -> URL? {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else { return nil }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
              !email.contains(where: { $0.isWhitespace || "?&#/:,;<>\"".contains($0) }) else { return nil }
        return URL(string: "mailto:\(email)")
    }

    /// "1.0.0 (1)" from an Info.plist dictionary. Just "1.0.0" without a build number, nil without a version.
    static func version(info: [String: Any]?) -> String? {
        func value(_ key: String) -> String? {
            guard let text = (info?[key] as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
            return text
        }
        guard let version = value("CFBundleShortVersionString") else { return nil }
        guard let build = value("CFBundleVersion") else { return version }
        return "\(version) (\(build))"
    }
}
