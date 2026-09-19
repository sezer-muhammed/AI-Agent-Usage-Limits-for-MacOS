import Foundation

/// Normalized usage for one account at one point in time.
///
/// Missing values stay `nil`; AI Meter never fabricates quota numbers.
public struct UsageSnapshot: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(provider.id)/\(accountID)/\(capturedAt.timeIntervalSince1970)" }

    public let provider: Provider
    public let accountID: String
    public let capturedAt: Date

    public let windows: [RateLimitWindow]

    public let spendTodayUSD: Decimal?
    public let spendWeekUSD: Decimal?
    public let spendMonthUSD: Decimal?

    public let creditsRemainingUSD: Decimal?

    public let activeModelID: String?

    /// Free-form, provider-supplied plan label ("pro", "free tier", …) when exposed.
    public let planLabel: String?

    public init(
        provider: Provider,
        accountID: String,
        capturedAt: Date,
        windows: [RateLimitWindow] = [],
        spendTodayUSD: Decimal? = nil,
        spendWeekUSD: Decimal? = nil,
        spendMonthUSD: Decimal? = nil,
        creditsRemainingUSD: Decimal? = nil,
        activeModelID: String? = nil,
        planLabel: String? = nil
    ) {
        self.provider = provider
        self.accountID = accountID
        self.capturedAt = capturedAt
        self.windows = windows
        self.spendTodayUSD = spendTodayUSD
        self.spendWeekUSD = spendWeekUSD
        self.spendMonthUSD = spendMonthUSD
        self.creditsRemainingUSD = creditsRemainingUSD
        self.activeModelID = activeModelID
        self.planLabel = planLabel
    }

    /// The window the UI should lead with for this account.
    public var primaryWindow: RateLimitWindow? {
        windows.max { ($0.usedFraction ?? -1) < ($1.usedFraction ?? -1) }
    }
}
