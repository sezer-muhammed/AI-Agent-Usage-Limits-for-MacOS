import Foundation

/// Wire types for the Codex app-server protocol.
///
/// Verified against `codex app-server generate-json-schema` from the installed
/// Codex CLI (0.154.0). The protocol is marked experimental upstream, so every
/// field here is optional and unknown fields are ignored: a Codex upgrade that
/// adds or moves a field degrades one value rather than breaking the refresh.
///
/// Keep these separate from Core. If the protocol changes incompatibly, add a
/// `CodexV2DTO` alongside rather than mutating this one.
enum CodexDTO {
    // MARK: initialize

    struct InitializeParams: Encodable, Sendable {
        let clientInfo: ClientInfo
    }

    struct ClientInfo: Encodable, Sendable {
        let name: String
        let version: String
    }

    struct InitializeResponse: Decodable, Sendable {
        let userAgent: String?
        let codexHome: String?
    }

    // MARK: account/read

    struct GetAccountResponse: Decodable, Sendable {
        let account: Account?
        let requiresOpenaiAuth: Bool?
    }

    struct Account: Decodable, Sendable {
        /// "chatgpt", "apiKey" or "amazonBedrock".
        let type: String?
        let email: String?
        let planType: String?
    }

    // MARK: account/rateLimits/read

    struct GetAccountRateLimitsResponse: Decodable, Sendable {
        let accountId: String?
        let rateLimits: RateLimitSnapshot?
        /// Multi-bucket view keyed by metered limit id (for example "codex").
        let rateLimitsByLimitId: [String: RateLimitSnapshot]?
        let ordinaryUsageAllowed: Bool?
    }

    struct RateLimitSnapshot: Decodable, Sendable {
        let limitId: String?
        let limitName: String?
        let planType: String?
        let primary: RateLimitWindowDTO?
        let secondary: RateLimitWindowDTO?
        let credits: CreditsSnapshot?
        let rateLimitReachedType: String?
    }

    struct RateLimitWindowDTO: Decodable, Sendable {
        let usedPercent: Double?
        /// Unix epoch seconds.
        let resetsAt: Double?
        let windowDurationMins: Int?
    }

    struct CreditsSnapshot: Decodable, Sendable {
        /// Decimal string, or absent.
        let balance: String?
        let hasCredits: Bool?
        let unlimited: Bool?
    }

    // MARK: account/usage/read

    struct GetAccountTokenUsageResponse: Decodable, Sendable {
        let summary: TokenUsageSummary?
        let dailyUsageBuckets: [DailyUsageBucket]?
    }

    struct TokenUsageSummary: Decodable, Sendable {
        let lifetimeTokens: Int64?
        let peakDailyTokens: Int64?
        let currentStreakDays: Int64?
        let longestStreakDays: Int64?
    }

    struct DailyUsageBucket: Decodable, Sendable {
        let startDate: String?
        let tokens: Int64?
    }

    // MARK: model/list

    struct ModelListResponse: Decodable, Sendable {
        let data: [Model]?
        let nextCursor: String?
    }

    struct Model: Decodable, Sendable {
        let id: String?
        let model: String?
        let displayName: String?
        let description: String?
        let isDefault: Bool?
        let hidden: Bool?
        let inputModalities: [String]?
    }
}
