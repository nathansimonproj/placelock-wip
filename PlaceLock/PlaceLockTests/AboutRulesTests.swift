import Foundation
import Testing
@testable import PlaceLock

/// The About section: version text, and links that stay hidden until they're real.
struct AboutRulesTests {
    // MARK: Links

    @Test func unsetLinksAreHidden() {
        let links = AboutRules.links(privacyPolicy: nil, supportURL: nil, supportEmail: nil)
        #expect(links == AboutRules.Links(privacyPolicy: nil, support: nil))
    }

    @Test func blankLinksAreHidden() {
        let links = AboutRules.links(privacyPolicy: "  ", supportURL: "", supportEmail: " \n")
        #expect(links.privacyPolicy == nil)
        #expect(links.support == nil)
    }

    @Test func httpsLinksAreKept() {
        let links = AboutRules.links(privacyPolicy: " https://example.com/privacy ", supportURL: "https://example.com/help",
                                     supportEmail: nil)
        #expect(links.privacyPolicy == URL(string: "https://example.com/privacy"))
        #expect(links.support == URL(string: "https://example.com/help"))
    }

    @Test func nonHttpsLinksAreHidden() {
        for text in ["http://example.com/privacy", "example.com/privacy", "https://", "mailto:a@b.com", "file:///privacy"] {
            #expect(AboutRules.webURL(text) == nil, "\(text)")
        }
    }

    @Test func supportEmailWinsOverSupportPage() {
        let links = AboutRules.links(privacyPolicy: nil, supportURL: "https://example.com/help",
                                     supportEmail: "help@example.com")
        #expect(links.support == URL(string: "mailto:help@example.com"))
    }

    @Test func badSupportEmailFallsBackToSupportPage() {
        let links = AboutRules.links(privacyPolicy: nil, supportURL: "https://example.com/help", supportEmail: "help")
        #expect(links.support == URL(string: "https://example.com/help"))
    }

    @Test func onlyPlainEmailAddressesBecomeMailLinks() {
        #expect(AboutRules.mailURL("help@example.com") == URL(string: "mailto:help@example.com"))
        for text in ["help", "@example.com", "help@", "help@example", "a@b@c.com", "help @example.com",
                     "help@example.com?subject=x", "help@.com", "help@example.com."] {
            #expect(AboutRules.mailURL(text) == nil, "\(text)")
        }
    }

    // MARK: Version

    @Test func versionShowsBuildNumber() {
        let info = ["CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1"]
        #expect(AboutRules.version(info: info) == "1.0.0 (1)")
    }

    @Test func versionWithoutBuildNumber() {
        #expect(AboutRules.version(info: ["CFBundleShortVersionString": "1.0.0"]) == "1.0.0")
        #expect(AboutRules.version(info: ["CFBundleShortVersionString": "1.0.0", "CFBundleVersion": " "]) == "1.0.0")
    }

    @Test func noVersionHidesTheRow() {
        #expect(AboutRules.version(info: nil) == nil)
        #expect(AboutRules.version(info: ["CFBundleVersion": "1"]) == nil)
        #expect(AboutRules.version(info: ["CFBundleShortVersionString": 1]) == nil)
    }

    @Test func appBundleHasAVersion() {
        // The test host is the app, so this is the real Info.plist (1.0.0 (1) or later).
        #expect(AboutRules.version(info: Bundle.main.infoDictionary) != nil)
    }
}
