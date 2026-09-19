import Foundation

/// One coherent view of everything AI Meter knows, assembled after a refresh
/// round finishes. The UI and the widget both render from this — never from a
/// half-updated mix of provider results.
public struct DashboardSnapshot: Codable, Sendable, Hashable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date

    public let usage: [UsageSnapshot]
    public let statuses: [ProviderStatus]

    public let bestFree: [RankingCategory: AIModel]
    public let recentChanges: [ModelChangeEvent]

    /// Genuine free variants in the current catalog.
    public let freeModelCount: Int?

    /// The most recently published free variant, when the catalog dates them.
    public let newestFreeModel: AIModel?

    public init(
        generatedAt: Date,
        usage: [UsageSnapshot],
        statuses: [ProviderStatus],
        bestFree: [RankingCategory: AIModel],
        recentChanges: [ModelChangeEvent] = [],
        freeModelCount: Int? = nil,
        newestFreeModel: AIModel? = nil
    ) {
        self.schemaVersion = Self.schemaVersion
        self.generatedAt = generatedAt
        self.usage = usage
        self.statuses = statuses
        self.bestFree = bestFree
        self.recentChanges = recentChanges
        self.freeModelCount = freeModelCount
        self.newestFreeModel = newestFreeModel
    }

    public static let empty = DashboardSnapshot(
        generatedAt: .distantPast,
        usage: [],
        statuses: [],
        bestFree: [:]
    )
}
