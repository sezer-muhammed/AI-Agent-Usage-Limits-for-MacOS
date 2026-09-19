import AIMeterCore
import AIMeterProviders
import Foundation
import Observation

/// What the views observe. Holds the last coherent snapshot and nothing else:
/// no provider calls, no decoding, no file access.
@MainActor
@Observable
final class AppState {
    private(set) var snapshot: DashboardSnapshot = .empty
    private(set) var isRefreshing = false
    private(set) var models: [AIModel] = []
    /// Where the current scores came from, so the UI can label estimates.
    private(set) var benchmarkSource: BenchmarkSource?
    private(set) var benchmarkCapturedAt: Date?

    let environment: AppEnvironment

    init(environment: AppEnvironment = AppEnvironment()) {
        self.environment = environment
    }

    func start() async {
        await environment.bootstrap()
        snapshot = await environment.coordinator.snapshot()
        await refresh()
    }

    /// `force` is the user pressing refresh; otherwise cache freshness decides.
    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await environment.coordinator.refresh(force: force)
        snapshot = await environment.coordinator.snapshot()

        await refreshCatalog()
    }

    private func refreshCatalog() async {
        let adapter = OpenRouterModelsAdapter(client: environment.openRouterClient)
        guard let fetched = try? await adapter.fetchModels() else { return }

        models = await join(fetched, withFeedFrom: environment.benchmarks)
        try? await environment.modelRepository?.record(models: models, capturedAt: Date())

        let ranked = ModelRankingEngine().bestFree(models)
        await environment.coordinator.updateRankings(
            bestFree: ranked,
            changes: [],
            freeModelCount: models.filter(\.isFreeVariant).count
        )
        // The usage pass already wrote the widget payload; publish again so the
        // catalog's numbers are not held back until the next refresh.
        await environment.coordinator.publishWidgetSnapshot()
        snapshot = await environment.coordinator.snapshot()
    }

    /// Attaches feed scores to catalog entries by canonical id.
    ///
    /// A model the feed does not cover keeps its place in the catalog with no
    /// benchmark, rather than being dropped or given a filler score.
    private func join(
        _ catalog: [AIModel],
        withFeedFrom provider: FileBenchmarkProvider
    ) async -> [AIModel] {
        guard provider.isConfigured else {
            benchmarkSource = nil
            benchmarkCapturedAt = nil
            return catalog
        }

        let scores = (try? await provider.benchmarks()) ?? [:]
        let availability = (try? await provider.availability()) ?? [:]

        if let feed = try? provider.load() {
            benchmarkSource = feed.source
            benchmarkCapturedAt = feed.capturedAt
        }

        return catalog.map { model in
            model.attaching(
                benchmark: scores[model.canonicalID],
                availability: availability[model.canonicalID]
            )
        }
    }

    /// Set when the scores on screen are estimates rather than measurements.
    var benchmarkEstimateNotice: String? {
        guard let benchmarkSource, benchmarkSource.isEstimate else { return nil }
        return "Scores are estimates, not measured benchmarks"
    }

    // MARK: Derived view data

    var accounts: [UsageSnapshot] {
        snapshot.usage.sorted { $0.accountID < $1.accountID }
    }

    func status(for accountID: String) -> ProviderStatus? {
        snapshot.statuses.first { $0.accountID == accountID }
    }

    func displayName(for usage: UsageSnapshot) -> String {
        status(for: usage.accountID)?.displayName ?? usage.provider.displayName
    }

    /// The most-consumed window across everything, for the menu bar icon state.
    var highestUsage: Double? {
        snapshot.usage.compactMap { $0.primaryWindow?.usedFraction }.max()
    }

    var freeModelCount: Int { models.filter(\.isFreeVariant).count }
}
