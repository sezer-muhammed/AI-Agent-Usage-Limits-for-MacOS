import Foundation

/// Persistence seam for usage history.
public protocol UsageSnapshotRepositoryProtocol: Sendable {
    func record(_ snapshot: UsageSnapshot) async throws
    func latest(accountID: String) async throws -> UsageSnapshot?
    func latestAll() async throws -> [UsageSnapshot]
    func history(accountID: String, since: Date) async throws -> [UsageSnapshot]
    func prune(rawOlderThan: Date) async throws
}

/// Persistence seam for the model catalog and its history.
public protocol ModelSnapshotRepositoryProtocol: Sendable {
    func record(models: [AIModel], capturedAt: Date) async throws
    func latestModels() async throws -> [AIModel]
    func recordRanks(_ ranks: [RankingCategory: [CanonicalModelID]], capturedAt: Date) async throws
    func latestRanks() async throws -> [RankingCategory: [CanonicalModelID]]
}

/// Writes the credential-free snapshot the widget reads.
public protocol WidgetSnapshotWriting: Sendable {
    func write(_ snapshot: WidgetSnapshot) async throws
}
