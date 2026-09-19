import Foundation

/// A provider-independent model identity.
///
/// Provider model IDs differ (`deepseek/deepseek-chat:free`, `gpt-5-codex`,
/// `claude-opus-4-6-20260115`), so benchmarks are joined on this instead of on
/// display names.
public struct CanonicalModelID: Hashable, Codable, Sendable, CustomStringConvertible,
    ExpressibleByStringLiteral
{
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String { rawValue }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
}
