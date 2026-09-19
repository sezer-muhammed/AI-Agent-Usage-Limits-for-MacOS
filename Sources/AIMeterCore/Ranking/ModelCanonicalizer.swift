import Foundation

/// Maps provider-specific model identifiers onto a shared identity.
///
/// Display-name matching is deliberately not used: providers rename models and
/// reuse names across versions. Explicit aliases win, then a structural
/// normalization of the raw ID.
public struct ModelCanonicalizer: Sendable {
    /// Exact provider ID → canonical ID overrides, for cases normalization gets wrong.
    private let aliases: [String: CanonicalModelID]

    public init(aliases: [String: CanonicalModelID] = ModelCanonicalizer.defaultAliases) {
        self.aliases = aliases
    }

    public func canonicalID(forProviderModelID rawID: String) -> CanonicalModelID {
        let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let alias = aliases[trimmed] { return alias }

        var identifier = trimmed

        // Drop an OpenRouter variant suffix (":free", ":nitro", ":extended").
        if let colon = identifier.firstIndex(of: ":") {
            identifier = String(identifier[identifier.startIndex..<colon])
        }

        // Drop the vendor namespace ("deepseek/deepseek-chat" -> "deepseek-chat").
        if let slash = identifier.lastIndex(of: "/") {
            identifier = String(identifier[identifier.index(after: slash)...])
        }

        // Drop a trailing release date ("claude-opus-4-6-20260115").
        identifier = Self.trailingDatePattern.stringByReplacingMatches(
            in: identifier,
            range: NSRange(identifier.startIndex..., in: identifier),
            withTemplate: ""
        )

        // "-latest" / "-preview" are pointers to a version, not a distinct model.
        for suffix in ["-latest", "-preview"] where identifier.hasSuffix(suffix) {
            identifier = String(identifier.dropLast(suffix.count))
        }

        if let alias = aliases[identifier] { return alias }
        return CanonicalModelID(identifier)
    }

    /// The vendor portion of a namespaced provider ID, when there is one.
    public func vendor(forProviderModelID rawID: String) -> String {
        guard let slash = rawID.firstIndex(of: "/") else { return "unknown" }
        return String(rawID[rawID.startIndex..<slash]).lowercased()
    }

    private static let trailingDatePattern = try! NSRegularExpression(
        pattern: "[-@](20[0-9]{6}|20[0-9]{2}-[0-9]{2}-[0-9]{2})$"
    )

    /// Seeded with the cases where structural normalization is not enough.
    /// Extend as real provider data proves it necessary — never guess.
    public static let defaultAliases: [String: CanonicalModelID] = [
        "gpt-5-codex": "gpt-5-codex",
        "gpt-5.1-codex": "gpt-5.1-codex",
        "gpt-5.1-codex-max": "gpt-5.1-codex-max",
    ]
}
