import Foundation

/// Per-provider result of the last refresh attempt, kept so the dashboard can
/// show "OpenRouter ✓ / Codex ✕" without discarding cached data.
public struct ProviderStatus: Codable, Sendable, Hashable {
    public let accountID: String
    public let provider: Provider

    public let lastSuccessAt: Date?
    public let lastAttemptAt: Date?
    public let lastErrorDescription: String?

    public init(
        accountID: String,
        provider: Provider,
        lastSuccessAt: Date?,
        lastAttemptAt: Date?,
        lastErrorDescription: String? = nil
    ) {
        self.accountID = accountID
        self.provider = provider
        self.lastSuccessAt = lastSuccessAt
        self.lastAttemptAt = lastAttemptAt
        self.lastErrorDescription = lastErrorDescription
    }

    public var isHealthy: Bool { lastErrorDescription == nil && lastSuccessAt != nil }

    public func freshness(
        now: Date = Date(),
        thresholds: Freshness.Thresholds = .default
    ) -> Freshness? {
        lastSuccessAt.map { Freshness.of($0, now: now, thresholds: thresholds) }
    }
}
