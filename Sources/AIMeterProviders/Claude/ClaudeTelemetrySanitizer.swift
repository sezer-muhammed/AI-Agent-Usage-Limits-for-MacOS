import AIMeterCore
import Foundation

/// Turns a raw status-line payload into the sanitized telemetry file.
///
/// Lives in the provider layer so both the bridge executable and the tests use
/// exactly the same conversion.
public struct ClaudeTelemetrySanitizer: Sendable {
    public init() {}

    public func sanitize(statusLineJSON data: Data, capturedAt: Date = Date()) throws
        -> ClaudeTelemetry
    {
        let payload: ClaudeStatusLinePayload
        do {
            payload = try JSONDecoder().decode(ClaudeStatusLinePayload.self, from: data)
        } catch {
            throw ProviderError.malformedResponse("Claude status-line payload")
        }

        return ClaudeTelemetry(
            capturedAt: capturedAt,
            model: payload.model.map {
                ClaudeTelemetry.Model(id: $0.id, displayName: $0.displayName)
            },
            rateLimits: payload.rateLimits.map { limits in
                ClaudeTelemetry.RateLimits(
                    fiveHour: Self.window(limits.fiveHour),
                    sevenDay: Self.window(limits.sevenDay),
                    spendLimit: Self.window(limits.spendLimit)
                )
            }
        )
    }

    private static func window(_ window: ClaudeStatusLinePayload.Window?) -> ClaudeTelemetry.Window? {
        guard let window else { return nil }
        return ClaudeTelemetry.Window(
            usedPercentage: window.usedPercentage,
            resetsAt: window.resetsAt.map(Date.init(timeIntervalSince1970:))
        )
    }
}
