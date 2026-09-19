import Foundation

/// Runs provider refreshes, keeps them from overlapping, and assembles one
/// coherent dashboard snapshot when they finish.
///
/// Rules it enforces:
/// - a provider failure never clears that provider's cached data;
/// - a refresh already in flight is joined, not duplicated;
/// - the widget snapshot is written once, after everything has settled.
public actor RefreshCoordinator {
    public struct Registration: Sendable {
        public let account: ProviderAccount
        public let policy: RefreshPolicy
        public let fetch: @Sendable () async throws -> UsageSnapshot

        public init(
            account: ProviderAccount,
            policy: RefreshPolicy,
            fetch: @escaping @Sendable () async throws -> UsageSnapshot
        ) {
            self.account = account
            self.policy = policy
            self.fetch = fetch
        }
    }

    public enum State: Sendable, Equatable {
        case idle
        case refreshing
    }

    private var registrations: [String: Registration] = [:]
    private var snapshots: [String: UsageSnapshot] = [:]
    private var statuses: [String: ProviderStatus] = [:]
    private var inFlight: Task<Void, Never>?

    private let usageRepository: (any UsageSnapshotRepositoryProtocol)?
    private let widgetWriter: (any WidgetSnapshotWriting)?
    private let now: @Sendable () -> Date

    public private(set) var state: State = .idle
    public private(set) var bestFree: [RankingCategory: AIModel] = [:]
    public private(set) var recentChanges: [ModelChangeEvent] = []

    public init(
        usageRepository: (any UsageSnapshotRepositoryProtocol)? = nil,
        widgetWriter: (any WidgetSnapshotWriting)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.usageRepository = usageRepository
        self.widgetWriter = widgetWriter
        self.now = now
    }

    public func register(_ registration: Registration) {
        registrations[registration.account.id] = registration
    }

    /// Seeds in-memory state from the database so the UI renders before any
    /// network call happens.
    public func primeFromCache() async {
        guard let usageRepository else { return }
        guard let cached = try? await usageRepository.latestAll() else { return }
        for snapshot in cached {
            snapshots[snapshot.accountID] = snapshot
        }
    }

    public func updateRankings(bestFree: [RankingCategory: AIModel], changes: [ModelChangeEvent]) {
        self.bestFree = bestFree
        self.recentChanges = changes
    }

    public func snapshot() -> DashboardSnapshot {
        DashboardSnapshot(
            generatedAt: now(),
            usage: Array(snapshots.values).sorted { $0.accountID < $1.accountID },
            statuses: Array(statuses.values).sorted { $0.accountID < $1.accountID },
            bestFree: bestFree,
            recentChanges: recentChanges
        )
    }

    /// Refreshes every registration whose cache has aged out (or all of them
    /// when `force` is set). Concurrent callers join the running pass.
    public func refresh(force: Bool = false) async {
        if let inFlight {
            await inFlight.value
            return
        }

        let task = Task { await performRefresh(force: force) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func performRefresh(force: Bool) async {
        state = .refreshing
        defer { state = .idle }

        let due = registrations.values.filter { registration in
            force
                || registration.policy.usageIsStale(
                    lastSuccess: statuses[registration.account.id]?.lastSuccessAt,
                    now: now()
                )
        }

        guard !due.isEmpty else { return }

        // Providers are independent, so they run concurrently and their failures
        // are isolated from one another.
        let results = await withTaskGroup(
            of: (String, Result<UsageSnapshot, any Error>).self
        ) { group in
            for registration in due {
                group.addTask {
                    do {
                        return (registration.account.id, .success(try await registration.fetch()))
                    } catch {
                        return (registration.account.id, .failure(error))
                    }
                }
            }

            var collected: [(String, Result<UsageSnapshot, any Error>)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        for (accountID, result) in results {
            guard let registration = registrations[accountID] else { continue }
            let attemptedAt = now()

            switch result {
            case .success(let snapshot):
                snapshots[accountID] = snapshot
                statuses[accountID] = ProviderStatus(
                    accountID: accountID,
                    provider: registration.account.provider,
                    lastSuccessAt: attemptedAt,
                    lastAttemptAt: attemptedAt
                )
                try? await usageRepository?.record(snapshot)

            case .failure(let error):
                // Cached data stays put; only the status reflects the failure.
                statuses[accountID] = ProviderStatus(
                    accountID: accountID,
                    provider: registration.account.provider,
                    lastSuccessAt: statuses[accountID]?.lastSuccessAt,
                    lastAttemptAt: attemptedAt,
                    lastErrorDescription: (error as? ProviderError)?.errorDescription
                        ?? error.localizedDescription
                )
                AIMeterLog.refresh.error(
                    "Refresh failed for \(accountID, privacy: .public)"
                )
            }
        }

        // One widget write per pass, after every provider has settled.
        try? await widgetWriter?.write(WidgetSnapshot(dashboard: snapshot(), now: now()))
    }
}
