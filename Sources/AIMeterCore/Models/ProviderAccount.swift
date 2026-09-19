import Foundation

/// One configured account belonging to a provider.
///
/// Codex supports two accounts, each backed by its own isolated `CODEX_HOME`.
/// The UI must not special-case providers: it renders whatever accounts exist.
public struct ProviderAccount: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let provider: Provider
    public let displayName: String

    /// Filesystem profile this account is driven from, when the provider needs one
    /// (`CODEX_HOME` for Codex). `nil` for purely network-backed providers.
    public let profilePath: String?

    public init(id: String, provider: Provider, displayName: String, profilePath: String? = nil) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.profilePath = profilePath
    }
}
