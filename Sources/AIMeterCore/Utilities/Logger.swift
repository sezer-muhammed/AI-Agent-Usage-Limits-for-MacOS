import OSLog

/// Unified-logging handles, one per subsystem area.
///
/// Nothing that could carry a credential — API keys, OAuth tokens, authorization
/// headers, raw provider payloads — is ever passed to these.
public enum AIMeterLog {
    public static let subsystem = "com.sezer-muhammed.aimeter"

    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let openRouter = Logger(subsystem: subsystem, category: "openrouter")
    public static let claude = Logger(subsystem: subsystem, category: "claude")
    public static let codex = Logger(subsystem: subsystem, category: "codex")
    public static let storage = Logger(subsystem: subsystem, category: "storage")
    public static let widget = Logger(subsystem: subsystem, category: "widget")
    public static let refresh = Logger(subsystem: subsystem, category: "refresh")
}
