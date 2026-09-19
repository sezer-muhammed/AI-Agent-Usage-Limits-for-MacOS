import Foundation

/// How much to trust a cached value's age. The UI must never present stale
/// telemetry as if it were live.
public enum Freshness: String, Codable, Sendable {
    case fresh
    case slightlyStale
    case stale

    public struct Thresholds: Sendable, Hashable {
        public let slightlyStaleAfter: TimeInterval
        public let staleAfter: TimeInterval

        public init(slightlyStaleAfter: TimeInterval, staleAfter: TimeInterval) {
            self.slightlyStaleAfter = slightlyStaleAfter
            self.staleAfter = staleAfter
        }

        /// Claude telemetry is event-driven, so it ages faster than a polled API.
        public static let claude = Thresholds(slightlyStaleAfter: 30 * 60, staleAfter: 120 * 60)
        public static let `default` = Thresholds(slightlyStaleAfter: 60 * 60, staleAfter: 6 * 60 * 60)
    }

    public static func of(
        _ capturedAt: Date,
        now: Date = Date(),
        thresholds: Thresholds = .default
    ) -> Freshness {
        let age = now.timeIntervalSince(capturedAt)
        if age >= thresholds.staleAfter { return .stale }
        if age >= thresholds.slightlyStaleAfter { return .slightlyStale }
        return .fresh
    }
}
