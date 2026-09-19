import Foundation

/// How stale a cached value may get before a refresh is worth running.
///
/// These are cache-freshness checks, not timers. Nothing here polls: a refresh
/// happens on launch, when the menu opens, on an explicit request, or from a
/// system-coordinated background activity.
public struct RefreshPolicy: Sendable, Hashable {
    public let usageMaxAge: TimeInterval
    public let catalogMaxAge: TimeInterval
    public let benchmarkMaxAge: TimeInterval

    public init(usageMaxAge: TimeInterval, catalogMaxAge: TimeInterval, benchmarkMaxAge: TimeInterval) {
        self.usageMaxAge = usageMaxAge
        self.catalogMaxAge = catalogMaxAge
        self.benchmarkMaxAge = benchmarkMaxAge
    }

    public static let openRouter = RefreshPolicy(
        usageMaxAge: 15 * 60,
        catalogMaxAge: 6 * 60 * 60,
        benchmarkMaxAge: 6 * 60 * 60
    )

    /// Starting a Codex server is not free, so its cache is allowed to age more.
    public static let codex = RefreshPolicy(
        usageMaxAge: 30 * 60,
        catalogMaxAge: 6 * 60 * 60,
        benchmarkMaxAge: 12 * 60 * 60
    )

    /// Claude is event-driven through the bridge: AI Meter never pulls it.
    public static let claude = RefreshPolicy(
        usageMaxAge: 0,
        catalogMaxAge: .greatestFiniteMagnitude,
        benchmarkMaxAge: .greatestFiniteMagnitude
    )

    public func usageIsStale(lastSuccess: Date?, now: Date = Date()) -> Bool {
        guard let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= usageMaxAge
    }
}
