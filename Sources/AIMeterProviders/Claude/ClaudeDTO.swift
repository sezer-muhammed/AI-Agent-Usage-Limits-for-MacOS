import Foundation

/// The subset of Claude Code's status-line stdin payload that AI Meter reads.
///
/// Verified against the documented status-line schema (Claude Code 2.1.x).
/// Everything else in that payload — cwd, session id, transcript path, cost,
/// prompt cache, PR state — is deliberately not decoded: what is never read
/// cannot be leaked.
///
/// `rate_limits` is absent for non-subscription accounts and before the first
/// API response of a session, and each window can be absent independently.
struct ClaudeStatusLinePayload: Decodable, Sendable {
    struct Model: Decodable, Sendable {
        let id: String?
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    struct Window: Decodable, Sendable {
        let usedPercentage: Double?
        /// Unix epoch seconds.
        let resetsAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }
    }

    struct RateLimits: Decodable, Sendable {
        let fiveHour: Window?
        let sevenDay: Window?
        let spendLimit: Window?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case spendLimit = "spend_limit"
        }
    }

    let model: Model?
    let rateLimits: RateLimits?
    let version: String?

    enum CodingKeys: String, CodingKey {
        case model
        case rateLimits = "rate_limits"
        case version
    }
}
