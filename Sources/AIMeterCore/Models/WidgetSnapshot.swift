import Foundation

/// The tiny, credential-free payload handed to WidgetKit through the App Group.
/// The widget performs no networking and never opens the history database.
extension WidgetSnapshot.Window {
    init(_ window: RateLimitWindow) {
        self.init(usedFraction: window.usedFraction, resetsAt: window.resetsAt)
    }
}

public struct WidgetSnapshot: Codable, Sendable, Hashable {
    /// v3 adds the catalog column: newest free model alongside the best one.
    public static let schemaVersion = 3

    public struct BestModel: Codable, Sendable, Hashable {
        public let name: String
        public let score: Double?
        /// True when the score was estimated rather than measured. The widget
        /// marks these so a guess never reads as a benchmark result.
        public let isEstimate: Bool

        public init(name: String, score: Double?, isEstimate: Bool = false) {
            self.name = name
            self.score = score
            self.isEstimate = isEstimate
        }
    }

    /// One quota window, reduced to what a widget can draw.
    public struct Window: Codable, Sendable, Hashable {
        public let usedFraction: Double?
        public let resetsAt: Date?

        public init(usedFraction: Double?, resetsAt: Date?) {
            self.usedFraction = usedFraction
            self.resetsAt = resetsAt
        }
    }

    public struct AccountUsage: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public let displayName: String

        /// Short window (5-hour/session) and long window (weekly), shown as two
        /// columns. Either can be absent: not every provider reports both.
        public let shortWindow: Window?
        public let longWindow: Window?

        /// For an account whose story is not a percentage — OpenRouter's credits
        /// and free-model count, for instance.
        public let detail: String?

        public let isStale: Bool

        public init(
            id: String,
            displayName: String,
            shortWindow: Window?,
            longWindow: Window?,
            detail: String? = nil,
            isStale: Bool
        ) {
            self.id = id
            self.displayName = displayName
            self.shortWindow = shortWindow
            self.longWindow = longWindow
            self.detail = detail
            self.isStale = isStale
        }

        /// Whichever window is closest to being spent, for the small widget.
        public var leadingWindow: Window? {
            [shortWindow, longWindow]
                .compactMap { $0 }
                .max { ($0.usedFraction ?? -1) < ($1.usedFraction ?? -1) }
        }
    }

    public let schemaVersion: Int
    public let generatedAt: Date
    public let bestFree: [String: BestModel]
    public let accounts: [AccountUsage]

    /// How many genuine free variants the catalog currently offers. Shown when
    /// no benchmark source is configured, so the row says something true rather
    /// than a score nobody measured.
    public let freeModelCount: Int?

    /// Most recently published free variant, for the catalog column.
    public let newestFreeModel: BestModel?
    public let newestFreeModelDate: Date?

    public init(
        generatedAt: Date,
        bestFree: [String: BestModel],
        accounts: [AccountUsage],
        freeModelCount: Int? = nil,
        newestFreeModel: BestModel? = nil,
        newestFreeModelDate: Date? = nil
    ) {
        self.schemaVersion = Self.schemaVersion
        self.generatedAt = generatedAt
        self.bestFree = bestFree
        self.accounts = accounts
        self.freeModelCount = freeModelCount
        self.newestFreeModel = newestFreeModel
        self.newestFreeModelDate = newestFreeModelDate
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
            best[category.rawValue] = BestModel(
                name: model.displayName,
                score: score,
                isEstimate: model.benchmark?.source.isEstimate ?? false
            )
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
                shortWindow: snapshot.shortWindow.map(Window.init),
                longWindow: snapshot.longWindow.map(Window.init),
                detail: Self.detail(for: snapshot),
                isStale: Freshness.of(snapshot.capturedAt, now: now) == .stale
            )
        }

        self.init(
            generatedAt: dashboard.generatedAt,
            bestFree: best,
            accounts: accounts,
            freeModelCount: dashboard.freeModelCount,
            newestFreeModel: dashboard.newestFreeModel.map {
                BestModel(
                    name: $0.displayName,
                    score: $0.benchmark?.intelligence,
                    isEstimate: $0.benchmark?.source.isEstimate ?? false
                )
            },
            newestFreeModelDate: dashboard.newestFreeModel?.createdAt
        )
    }

    /// An account with no quota windows still has something worth showing.
    private static func detail(for snapshot: UsageSnapshot) -> String? {
        guard snapshot.shortWindow == nil, snapshot.longWindow == nil else { return nil }

        if let credits = snapshot.creditsRemainingUSD {
            let amount = NSDecimalNumber(decimal: credits).doubleValue
            return String(format: "$%.2f left", amount)
        }
        return snapshot.planLabel
    }
}
