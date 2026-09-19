import Foundation
import Testing

@testable import AIMeterCore

@Suite("Freshness")
struct FreshnessTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Claude telemetry uses its own, stricter thresholds")
    func claudeThresholds() {
        let fortyMinutesAgo = now.addingTimeInterval(-40 * 60)

        #expect(Freshness.of(fortyMinutesAgo, now: now, thresholds: .claude) == .slightlyStale)
        // The same age is still fresh for a polled provider.
        #expect(Freshness.of(fortyMinutesAgo, now: now, thresholds: .default) == .fresh)
    }

    @Test("Old telemetry is reported as stale rather than as live")
    func staleAfterThreshold() {
        let threeHoursAgo = now.addingTimeInterval(-3 * 60 * 60)
        #expect(Freshness.of(threeHoursAgo, now: now, thresholds: .claude) == .stale)
    }
}

@Suite("Rate limit windows")
struct RateLimitWindowTests {
    @Test("Remaining is derived only when used is known")
    func remainingDerivation() {
        let known = RateLimitWindow(
            id: "w", kind: .weekly, usedFraction: 0.25, resetsAt: nil,
            durationMinutes: nil, label: "Weekly"
        )
        #expect(known.remainingFraction == 0.75)

        let unknown = RateLimitWindow(
            id: "w", kind: .weekly, usedFraction: nil, resetsAt: nil,
            durationMinutes: nil, label: "Weekly"
        )
        // Absent stays absent: a missing measurement is never rendered as zero.
        #expect(unknown.remainingFraction == nil)
    }

    @Test("Window duration classifies the window kind")
    func kindFromDuration() {
        #expect(RateLimitWindow.kind(forDurationMinutes: 300) == .fiveHour)
        #expect(RateLimitWindow.kind(forDurationMinutes: 10080) == .weekly)
        #expect(RateLimitWindow.kind(forDurationMinutes: nil) == .custom)
    }
}
