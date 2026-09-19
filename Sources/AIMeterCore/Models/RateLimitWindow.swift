import Foundation

/// A single quota window reported by a provider.
///
/// Providers do not expose equivalent limits, so every measurement is optional.
/// A `nil` value means "the provider did not tell us", never "zero".
public struct RateLimitWindow: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case session
        case fiveHour
        case daily
        case weekly
        case monthly
        case custom
    }

    public let id: String
    public let kind: Kind

    public let usedFraction: Double?
    public let remainingFraction: Double?

    public let resetsAt: Date?

    public let durationMinutes: Int?
    public let label: String

    public init(
        id: String,
        kind: Kind,
        usedFraction: Double?,
        remainingFraction: Double? = nil,
        resetsAt: Date?,
        durationMinutes: Int?,
        label: String
    ) {
        self.id = id
        self.kind = kind
        self.usedFraction = usedFraction
        // Only derive the complement when the provider gave us something to derive it from.
        self.remainingFraction = remainingFraction ?? usedFraction.map { 1 - $0 }
        self.resetsAt = resetsAt
        self.durationMinutes = durationMinutes
        self.label = label
    }

    /// Classifies a window from its duration when the provider labels windows only by length.
    public static func kind(forDurationMinutes minutes: Int?) -> Kind {
        switch minutes {
        case .some(let m) where m <= 60: .session
        case .some(let m) where m <= 60 * 8: .fiveHour
        case .some(let m) where m <= 60 * 24 * 2: .daily
        case .some(let m) where m <= 60 * 24 * 10: .weekly
        case .some(let m) where m <= 60 * 24 * 40: .monthly
        default: .custom
        }
    }
}
