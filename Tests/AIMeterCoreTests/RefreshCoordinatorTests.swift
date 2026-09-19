import Foundation
import Testing

@testable import AIMeterCore

private struct FailingProvider: Error {}

@Suite("Refresh coordination")
struct RefreshCoordinatorTests {
    private func account(_ id: String, provider: Provider) -> ProviderAccount {
        ProviderAccount(id: id, provider: provider, displayName: id)
    }

    @Test("A provider failure keeps that provider's cached data")
    func failureDoesNotClearCache() async {
        let coordinator = RefreshCoordinator()
        let shouldFail = Mutex(false)

        await coordinator.register(
            RefreshCoordinator.Registration(
                account: account("openrouter", provider: .openRouter),
                policy: .openRouter
            ) {
                if shouldFail.value { throw FailingProvider() }
                return UsageSnapshot(
                    provider: .openRouter,
                    accountID: "openrouter",
                    capturedAt: Date(),
                    spendTodayUSD: Decimal(string: "0.42")
                )
            }
        )

        await coordinator.refresh(force: true)
        #expect(await coordinator.snapshot().usage.first?.spendTodayUSD == Decimal(string: "0.42"))

        shouldFail.value = true
        await coordinator.refresh(force: true)

        let snapshot = await coordinator.snapshot()
        // The cached value survives …
        #expect(snapshot.usage.first?.spendTodayUSD == Decimal(string: "0.42"))
        // … and the failure is visible in the status instead.
        #expect(snapshot.statuses.first?.isHealthy == false)
        #expect(snapshot.statuses.first?.lastErrorDescription != nil)
    }

    @Test("One provider failing does not stop the others")
    func failuresAreIsolated() async {
        let coordinator = RefreshCoordinator()

        await coordinator.register(
            RefreshCoordinator.Registration(
                account: account("codex-personal", provider: .codex),
                policy: .codex
            ) { throw ProviderError.unauthorized }
        )
        await coordinator.register(
            RefreshCoordinator.Registration(
                account: account("claude", provider: .claude),
                policy: .claude
            ) {
                UsageSnapshot(provider: .claude, accountID: "claude", capturedAt: Date())
            }
        )

        await coordinator.refresh(force: true)
        let snapshot = await coordinator.snapshot()

        #expect(snapshot.usage.count == 1)
        #expect(snapshot.usage.first?.accountID == "claude")
        #expect(snapshot.statuses.count == 2)
    }

    @Test("A fresh cache is not refetched unless forced")
    func freshCacheIsNotRefetched() async {
        let coordinator = RefreshCoordinator()
        let calls = Mutex(0)

        await coordinator.register(
            RefreshCoordinator.Registration(
                account: account("openrouter", provider: .openRouter),
                policy: .openRouter
            ) {
                calls.value += 1
                return UsageSnapshot(
                    provider: .openRouter, accountID: "openrouter", capturedAt: Date()
                )
            }
        )

        await coordinator.refresh(force: true)
        await coordinator.refresh()

        #expect(calls.value == 1)
    }
}

/// Minimal mutable box for test bookkeeping across concurrency boundaries.
private final class Mutex<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: T

    init(_ value: T) { storage = value }

    var value: T {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}
