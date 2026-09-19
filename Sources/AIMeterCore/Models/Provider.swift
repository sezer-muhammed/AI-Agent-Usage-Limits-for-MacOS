import Foundation

/// A data source AI Meter can read from. Providers are identified by a stable
/// string so that persisted rows and widget snapshots survive renames.
public struct Provider: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = String

    public let id: ID
    public let displayName: String

    public init(id: ID, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    public static let openRouter = Provider(id: "openrouter", displayName: "OpenRouter")
    public static let claude = Provider(id: "claude", displayName: "Claude")
    public static let codex = Provider(id: "codex", displayName: "Codex")
}
