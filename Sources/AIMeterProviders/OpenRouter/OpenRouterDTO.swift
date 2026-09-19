import Foundation

/// Wire types for the OpenRouter REST API. These stay in the provider layer;
/// Core never sees them.
///
/// Verified against the live API (`/api/v1/models`, `/api/v1/key`,
/// `/api/v1/credits`). Every field the API may omit is optional, so a schema
/// change degrades a value to "unavailable" instead of failing the whole decode.
enum OpenRouterDTO {
    struct Envelope<T: Decodable & Sendable>: Decodable, Sendable {
        let data: T
    }

    struct ModelList: Decodable, Sendable {
        let data: [Model]
    }

    struct Model: Decodable, Sendable {
        let id: String
        let canonicalSlug: String?
        let name: String?
        let contextLength: Int?
        let architecture: Architecture?
        let pricing: Pricing?
        let topProvider: TopProvider?

        enum CodingKeys: String, CodingKey {
            case id
            case canonicalSlug = "canonical_slug"
            case name
            case contextLength = "context_length"
            case architecture
            case pricing
            case topProvider = "top_provider"
        }
    }

    struct Architecture: Decodable, Sendable {
        let modality: String?
        let inputModalities: [String]?
        let outputModalities: [String]?

        enum CodingKeys: String, CodingKey {
            case modality
            case inputModalities = "input_modalities"
            case outputModalities = "output_modalities"
        }
    }

    /// Prices arrive as decimal strings in USD per token.
    struct Pricing: Decodable, Sendable {
        let prompt: String?
        let completion: String?
    }

    struct TopProvider: Decodable, Sendable {
        let contextLength: Int?

        enum CodingKeys: String, CodingKey {
            case contextLength = "context_length"
        }
    }

    /// `/api/v1/key` — what this key has spent and what it is allowed to spend.
    /// Note these are dollar amounts, never a count of free requests.
    struct KeyInfo: Decodable, Sendable {
        let label: String?
        let usage: Double?
        let usageDaily: Double?
        let usageWeekly: Double?
        let usageMonthly: Double?
        let limit: Double?
        let limitRemaining: Double?
        let limitResetAt: String?
        let isFreeTier: Bool?

        enum CodingKeys: String, CodingKey {
            case label
            case usage
            case usageDaily = "usage_daily"
            case usageWeekly = "usage_weekly"
            case usageMonthly = "usage_monthly"
            case limit
            case limitRemaining = "limit_remaining"
            case limitResetAt = "limit_reset"
            case isFreeTier = "is_free_tier"
        }
    }

    /// `/api/v1/credits` — lifetime credits purchased and used.
    struct Credits: Decodable, Sendable {
        let totalCredits: Double?
        let totalUsage: Double?

        enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case totalUsage = "total_usage"
        }
    }
}
