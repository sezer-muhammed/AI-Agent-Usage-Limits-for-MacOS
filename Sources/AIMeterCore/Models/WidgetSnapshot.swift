import Foundation

/// The tiny, credential-free payload handed to WidgetKit through the App Group.
/// The widget performs no networking and never opens the history database.
public struct WidgetSnapshot: Codable, Sendable, Hashable {
    public static let schemaVersion = 1

    public struct BestModel: Codable, Sendable, Hashable {
        public let name: String
        public let score: Double?

        public init(name: String, score: Double?) {
            self.name = name
            self.score = score
        }
    }

    public struct AccountUsage: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public let displayName: String
        public let primaryUsage: Double?
        public let resetsAt: Date?
        public let isStale: Bool

        public init(
            id: String,
            displayName: String,
            primaryUsage: Double?,
            resetsAt: Date?,
            isStale: Bool
        ) {
            self.id = id
            self.displayName = displayName
            self.primaryUsage = primaryUsage
            self.resetsAt = resetsAt
            self.isStale = isStale
        }
    }

    public let schemaVersion: Int
    public let generatedAt: Date
    public let bestFree: [String: BestModel]
    public let accounts: [AccountUsage]

    public init(generatedAt: Date, bestFree: [String: BestModel], accounts: [AccountUsage]) {
        self.schemaVersion = Self.schemaVersion
        self.generatedAt = generatedAt
        self.bestFree = bestFree
        self.accounts = accounts
    }

    /// Projects a dashboard snapshot down to what a widget can render.
    public init(dashboard: DashboardSnapshot, now: Date = Date()) {
        var best: [String: BestModel] = [:]
        for (category, model) in dashboard.bestFree {
            let score: Double? =
                switch category {
                case .general: model.benchmark?.intelligence
                case .coding: model.benchmark?.coding
                case .agentic: model.benchmark?.agentic
                case .reliable: model.availability?.percentage
                }
            best[category.rawValue] = BestModel(name: model.displayName, score: score)
        }

        // Names come from the account, so two Codex profiles are distinguishable.
        let namesByAccount = Dictionary(
            dashboard.statuses.map { ($0.accountID, $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )

        let accounts = dashboard.usage.map { snapshot in
            AccountUsage(
                id: snapshot.accountID,
                displayName: namesByAccount[snapshot.accountID] ?? snapshot.provider.displayName,
                primaryUsage: snapshot.primaryWindow?.usedFraction,
                resetsAt: snapshot.primaryWindow?.resetsAt,
                isStale: Freshness.of(snapshot.capturedAt, now: now) == .stale
            )
        }

        self.init(generatedAt: dashboard.generatedAt, bestFree: best, accounts: accounts)
    }
}
