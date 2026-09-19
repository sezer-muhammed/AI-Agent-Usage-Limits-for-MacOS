import AIMeterCore
import Foundation
import Testing

@testable import AIMeterProviders

@Suite("Claude bridge")
struct ClaudeBridgeTests {
    let sanitizer = ClaudeTelemetrySanitizer()

    @Test("Rate limits are extracted from a status-line payload")
    func rateLimitsExtracted() throws {
        let telemetry = try sanitizer.sanitize(
            statusLineJSON: Fixture.data("Claude/statusline.json")
        )

        #expect(telemetry.model?.id == "claude-opus-5")
        #expect(telemetry.rateLimits?.fiveHour?.usedPercentage == 72.3)
        #expect(
            telemetry.rateLimits?.fiveHour?.resetsAt
                == Date(timeIntervalSince1970: 1_789_800_000)
        )
        #expect(telemetry.rateLimits?.sevenDay?.usedPercentage == 38.1)
        #expect(telemetry.rateLimits?.spendLimit == nil)
    }

    @Test("Nothing beyond usage metadata survives sanitizing")
    func sanitizedOutputCarriesNoSessionData() throws {
        let telemetry = try sanitizer.sanitize(
            statusLineJSON: Fixture.data("Claude/statusline.json")
        )

        let encoded = try DateFormatting.makeEncoder().encode(telemetry)
        let text = String(decoding: encoded, as: UTF8.self)

        // The fixture contains all of these; none may reach the written file.
        #expect(!text.contains("/fixture/working/directory"))
        #expect(!text.contains("transcript"))
        #expect(!text.contains("fixture-session"))
        #expect(!text.contains("total_cost_usd"))
    }

    @Test("A payload without rate limits yields no fabricated windows")
    func missingRateLimitsStayMissing() throws {
        let telemetry = try sanitizer.sanitize(
            statusLineJSON: Fixture.data("Claude/statusline-no-rate-limits.json")
        )

        #expect(telemetry.rateLimits == nil)
        #expect(telemetry.model?.displayName == "Sonnet")
    }

    @Test("Malformed input is a typed error, not a crash")
    func malformedInput() {
        #expect(throws: ProviderError.self) {
            try sanitizer.sanitize(statusLineJSON: Data("not json".utf8))
        }
    }

    @Test("The adapter reports the telemetry's own capture time")
    func adapterUsesCaptureTime() async throws {
        let telemetry = try sanitizer.sanitize(
            statusLineJSON: Fixture.data("Claude/statusline.json"),
            capturedAt: Date(timeIntervalSince1970: 1_789_790_000)
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-telemetry-\(UUID().uuidString).json")
        try DateFormatting.makeEncoder().encode(telemetry).write(to: url)

        let usage = try await ClaudeStatusAdapter(reader: ClaudeBridgeReader(url: url)).fetchUsage()

        #expect(usage.capturedAt == Date(timeIntervalSince1970: 1_789_790_000))
        #expect(usage.windows.count == 2)
        #expect(usage.windows.first?.usedFraction == 0.723)
        #expect(usage.primaryWindow?.kind == .fiveHour)
    }

    @Test("A missing telemetry file is reported as not configured")
    func missingTelemetryFile() {
        let reader = ClaudeBridgeReader(
            url: URL(fileURLWithPath: "/nonexistent/aimeter/claude-telemetry.json")
        )

        #expect(!reader.isInstalled)
        #expect(throws: ProviderError.self) { try reader.read() }
    }
}
