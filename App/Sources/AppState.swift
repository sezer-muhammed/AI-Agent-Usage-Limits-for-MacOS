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

        models = fetched
        try? await environment.modelRepository?.record(models: fetched, capturedAt: Date())

        let ranked = ModelRankingEngine().bestFree(fetched)
        await environment.coordinator.updateRankings(
            bestFree: ranked,
            changes: [],
            freeModelCount: fetched.filter(\.isFreeVariant).count
        )
        // The usage pass already wrote the widget payload; publish again so the
        // catalog's numbers are not held back until the next refresh.
        await environment.coordinator.publishWidgetSnapshot()
        snapshot = await environment.coordinator.snapshot()
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
