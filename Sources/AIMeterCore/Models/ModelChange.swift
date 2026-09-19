import Foundation

/// A meaningful difference between two catalog snapshots. Noise (unchanged
/// ranks, sub-threshold benchmark jitter) is filtered out before these are made.
public enum ModelChange: Codable, Sendable, Hashable {
    case appeared
    case disappeared
    case rankChanged(category: RankingCategory, from: Int, to: Int)
    case benchmarkChanged(dimension: BenchmarkDimension, from: Double?, to: Double?)
    case availabilityChanged(from: Double?, to: Double?)
}

public struct ModelChangeEvent: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(canonicalID.rawValue)|\(detectedAt.timeIntervalSince1970)|\(change)" }

    public let canonicalID: CanonicalModelID
    public let displayName: String
    public let change: ModelChange
    public let detectedAt: Date

    public init(
        canonicalID: CanonicalModelID,
        displayName: String,
        change: ModelChange,
        detectedAt: Date
    ) {
        self.canonicalID = canonicalID
        self.displayName = displayName
        self.change = change
        self.detectedAt = detectedAt
    }
}
