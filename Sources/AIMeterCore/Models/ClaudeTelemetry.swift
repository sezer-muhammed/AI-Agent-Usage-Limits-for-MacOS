import Foundation

/// The sanitized file the Claude bridge writes and the app reads.
///
/// This is the *entire* contract between Claude Code and AI Meter: usage
/// metadata only. No session content, no transcript path, no credentials —
/// AI Meter never touches Claude's authentication.
public struct ClaudeTelemetry: Codable, Sendable, Hashable {
    public static let schemaVersion = 1
    public static let fileName = "claude-telemetry.json"

    public struct Model: Codable, Sendable, Hashable {
        public let id: String?
        public let displayName: String?

        public init(id: String?, displayName: String?) {
            self.id = id
            self.displayName = displayName
        }
    }

    public struct Window: Codable, Sendable, Hashable {
        public let usedPercentage: Double?
        public let resetsAt: Date?

        public init(usedPercentage: Double?, resetsAt: Date?) {
            self.usedPercentage = usedPercentage
            self.resetsAt = resetsAt
        }
    }

    public struct RateLimits: Codable, Sendable, Hashable {
        public let fiveHour: Window?
        public let sevenDay: Window?
        public let spendLimit: Window?

        public init(fiveHour: Window?, sevenDay: Window?, spendLimit: Window?) {
            self.fiveHour = fiveHour
            self.sevenDay = sevenDay
            self.spendLimit = spendLimit
        }
    }

    public let schemaVersion: Int
    public let capturedAt: Date
    public let model: Model?
    public let rateLimits: RateLimits?

    public init(capturedAt: Date, model: Model?, rateLimits: RateLimits?) {
        self.schemaVersion = Self.schemaVersion
        self.capturedAt = capturedAt
        self.model = model
        self.rateLimits = rateLimits
    }

    /// Where the bridge writes and the app reads. Both sides derive it from here
    /// so the path is stated exactly once.
    public static func defaultURL(
        fileManager: FileManager = .default
    ) -> URL {
        let base =
            (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")

        return
            base
            .appendingPathComponent("AIMeter", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
