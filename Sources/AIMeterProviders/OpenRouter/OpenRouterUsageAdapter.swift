import AIMeterCore
import Foundation

/// Normalizes OpenRouter key/credit information into a `UsageSnapshot`.
///
/// Deliberate omission: OpenRouter's key endpoint reports dollars, not a count
/// of free requests consumed. This adapter therefore never produces an
/// "N / 50 free requests used" figure — spend, allowance and credits stay
/// distinct fields.
public struct OpenRouterUsageAdapter: UsageProvider {
    public let providerID: Provider.ID = Provider.openRouter.id
    public let accountID: String

    private let client: OpenRouterClient
    private let now: @Sendable () -> Date

    public init(
        accountID: String = "openrouter",
        client: OpenRouterClient,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.accountID = accountID
        self.client = client
        self.now = now
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let key = try await client.keyInfo()

        // Credits are a separate endpoint and may be unavailable on free-tier
        // keys; its failure must not lose the key information we already have.
        let credits = try? await client.credits()

        var windows: [RateLimitWindow] = []
        if let limit = key.limit, limit > 0, let usage = key.usage {
            windows.append(
                RateLimitWindow(
                    id: "\(accountID).key-limit",
                    kind: .custom,
                    usedFraction: min(max(usage / limit, 0), 1),
                    resetsAt: key.limitResetAt.flatMap(DateFormatting.iso8601),
                    durationMinutes: nil,
                    label: "Key spend limit"
                )
            )
        }

        let creditsRemaining: Decimal? = {
            guard let total = credits?.totalCredits, let used = credits?.totalUsage else {
                return key.limitRemaining.map { Decimal($0) }
            }
            return Decimal(total - used)
        }()

        return UsageSnapshot(
            provider: .openRouter,
            accountID: accountID,
            capturedAt: now(),
            windows: windows,
            spendTodayUSD: key.usageDaily.map { Decimal($0) },
            spendWeekUSD: key.usageWeekly.map { Decimal($0) },
            spendMonthUSD: key.usageMonthly.map { Decimal($0) },
            creditsRemainingUSD: creditsRemaining,
            activeModelID: nil,
            planLabel: key.isFreeTier == true ? "Free tier" : key.label
        )
    }
}
