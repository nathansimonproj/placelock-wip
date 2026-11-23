import Foundation
import Testing
@testable import PlaceLock

/// What VoiceOver reads for countdowns, durations, radii and the lock on Home.
struct SpokenRulesTests {
    @Test func durationsReadAsWords() {
        #expect(SpokenRules.duration((23 * 60 + 4) * 60) == "23 hours, 4 minutes")
        #expect(SpokenRules.duration(3600) == "1 hour")
        #expect(SpokenRules.duration(2 * 3600 + 59) == "2 hours")
        #expect(SpokenRules.duration(61 * 60) == "1 hour, 1 minute")
        #expect(SpokenRules.duration(45 * 60 + 30) == "45 minutes")
        #expect(SpokenRules.duration(30) == "0 minutes")
        #expect(SpokenRules.duration(-5) == "0 minutes")
    }

    @Test func timeLeftSaysNowInTheSameLastMinuteAsTheScreen() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        #expect(SpokenRules.timeLeft(until: now.addingTimeInterval(20.5 * 3600), now: now) == "20 hours, 30 minutes")
        #expect(SpokenRules.timeLeft(until: now.addingTimeInterval(61), now: now) == "1 minute")
        #expect(SpokenRules.timeLeft(until: now.addingTimeInterval(60), now: now) == "now")
        #expect(SpokenRules.timeLeft(until: now.addingTimeInterval(-10), now: now) == "now")
    }

    @Test func radiusReadsInMeters() {
        #expect(SpokenRules.meters(150) == "150 meters")
        #expect(SpokenRules.meters(1) == "1 meter")
    }

    @Test func lockSaysWhetherAppsAreBlocked() {
        #expect(SpokenRules.lock(unlocked: false, nothingBlocked: false) == "Apps blocked")
        #expect(SpokenRules.lock(unlocked: true, nothingBlocked: false) == "Apps unblocked")
        #expect(SpokenRules.lock(unlocked: false, nothingBlocked: true) == "No apps blocked yet")
    }
}
