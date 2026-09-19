import Foundation

/// Per-provider result of the last refresh attempt, kept so the dashboard can
/// show "OpenRouter ✓ / Codex ✕" without discarding cached data.
public struct ProviderStatus: Codable, Sendable, Hashable {
    public let accountID: String
    public let provider: Provider
    /// The account's own name ("Codex · Personal"), not the provider's. Two
    /// accounts of one provider must not render as two identical rows.
    public let displayName: String

    public let lastSuccessAt: Date?
    public let lastAttemptAt: Date?
    public let lastErrorDescription: String?

    public init(
        accountID: String,
        provider: Provider,
        displayName: String? = nil,
        lastSuccessAt: Date?,
        lastAttemptAt: Date?,
        lastErrorDescription: String? = nil
    ) {
        self.accountID = accountID
        self.provider = provider
        self.displayName = displayName ?? provider.displayName
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
