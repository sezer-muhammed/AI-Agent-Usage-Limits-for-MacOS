import Foundation
import Testing

@testable import AIMeterCore

@Suite("Persistence")
struct PersistenceTests {
    private func makeDatabase() async throws -> Database {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aimeter-tests-\(UUID().uuidString).sqlite")
        let database = try Database(url: url)
        try await Migrations.migrate(database)
        return database
    }

    @Test("Migrations are idempotent")
    func migrationsRunOnce() async throws {
        let database = try await makeDatabase()
        try await Migrations.migrate(database)

        let version = try await database.query("PRAGMA user_version") { Int($0.int(0) ?? 0) }.first
        #expect(version == Migrations.all.count)
    }

    @Test("A usage snapshot round-trips with its windows")
    func snapshotRoundTrip() async throws {
        let database = try await makeDatabase()
        let repository = UsageSnapshotRepository(database: database) { _ in .claude }

        let captured = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = UsageSnapshot(
            provider: .claude,
            accountID: "claude",
            capturedAt: captured,
            windows: [
                RateLimitWindow(
                    id: "claude.five-hour", kind: .fiveHour, usedFraction: 0.723,
                    resetsAt: captured.addingTimeInterval(3600), durationMinutes: 300,
                    label: "5-hour window"
                )
            ],
            spendTodayUSD: Decimal(string: "1.25"),
            planLabel: "Max"
        )

        try await repository.record(snapshot)
        let loaded = try await repository.latest(accountID: "claude")

        #expect(loaded?.accountID == "claude")
        #expect(loaded?.windows.count == 1)
        #expect(loaded?.windows.first?.kind == .fiveHour)
        #expect(loaded?.windows.first?.usedFraction == 0.723)
        #expect(loaded?.spendTodayUSD == Decimal(string: "1.25"))
        #expect(loaded?.planLabel == "Max")
    }

    @Test("Missing values stay missing across a round-trip")
    func nullsArePreserved() async throws {
        let database = try await makeDatabase()
        let repository = UsageSnapshotRepository(database: database) { _ in .codex }

        try await repository.record(
            UsageSnapshot(
                provider: .codex,
                accountID: "codex-personal",
                capturedAt: Date(),
                windows: [
                    RateLimitWindow(
                        id: "w", kind: .weekly, usedFraction: nil, resetsAt: nil,
                        durationMinutes: nil, label: "Weekly"
                    )
                ]
            )
        )

        let loaded = try await repository.latest(accountID: "codex-personal")
        #expect(loaded?.spendTodayUSD == nil)
        #expect(loaded?.windows.first?.usedFraction == nil)
        #expect(loaded?.windows.first?.remainingFraction == nil)
    }

    @Test("Pruning drops old rows and their windows")
    func pruning() async throws {
        let database = try await makeDatabase()
        let repository = UsageSnapshotRepository(database: database) { _ in .openRouter }

        let old = Date(timeIntervalSince1970: 1_000_000)
        try await repository.record(
            UsageSnapshot(
                provider: .openRouter, accountID: "openrouter", capturedAt: old,
                windows: [
                    RateLimitWindow(
                        id: "w", kind: .custom, usedFraction: 0.1, resetsAt: nil,
                        durationMinutes: nil, label: "Key"
                    )
                ]
            )
        )

        try await repository.prune(rawOlderThan: Date(timeIntervalSince1970: 2_000_000))

        #expect(try await repository.latest(accountID: "openrouter") == nil)
        let remainingWindows = try await database.query(
            "SELECT COUNT(*) FROM rate_limit_snapshots"
        ) { $0.int(0) ?? 0 }.first
        #expect(remainingWindows == 0)
    }

    @Test("Model ranks round-trip in order")
    func rankRoundTrip() async throws {
        let database = try await makeDatabase()
        let repository = ModelSnapshotRepository(database: database)

        try await repository.recordRanks(
            [.coding: [CanonicalModelID("first"), CanonicalModelID("second")]],
            capturedAt: Date()
        )

        let ranks = try await repository.latestRanks()
        #expect(ranks[.coding] == [CanonicalModelID("first"), CanonicalModelID("second")])
    }
}

@Suite("Widget snapshot")
struct WidgetSnapshotTests {
    @Test("Writing is atomic and the payload round-trips")
    func writeAndRead() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aimeter-widget-\(UUID().uuidString)")
        let writer = WidgetSnapshotWriter(containerURL: directory)

        let snapshot = WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            bestFree: ["general": .init(name: "Fixture", score: 34.5)],
            accounts: [
                .init(
                    id: "claude",
                    displayName: "Claude",
                    shortWindow: .init(usedFraction: 0.72, resetsAt: nil),
                    longWindow: .init(usedFraction: 0.31, resetsAt: nil),
                    isStale: false
                )
            ]
        )

        try await writer.write(snapshot)
        let loaded = try writer.read()

        #expect(loaded?.schemaVersion == WidgetSnapshot.schemaVersion)
        #expect(loaded?.accounts.first?.shortWindow?.usedFraction == 0.72)
        #expect(loaded?.accounts.first?.longWindow?.usedFraction == 0.31)
        #expect(loaded?.bestFree["general"]?.name == "Fixture")
    }

    @Test("Both windows survive the projection, in their own columns")
    func projection() {
        let dashboard = DashboardSnapshot(
            generatedAt: Date(),
            usage: [
                UsageSnapshot(
                    provider: .claude,
                    accountID: "claude",
                    capturedAt: Date(),
                    windows: [
                        RateLimitWindow(
                            id: "a", kind: .fiveHour, usedFraction: 0.4, resetsAt: nil,
                            durationMinutes: 300, label: "5h"
                        ),
                        RateLimitWindow(
                            id: "b", kind: .weekly, usedFraction: 0.9, resetsAt: nil,
                            durationMinutes: 10080, label: "7d"
                        ),
                    ]
                )
            ],
            statuses: [],
            bestFree: [:]
        )

        let widget = WidgetSnapshot(dashboard: dashboard)

        // The five-hour and weekly windows stay distinct …
        #expect(widget.accounts.first?.shortWindow?.usedFraction == 0.4)
        #expect(widget.accounts.first?.longWindow?.usedFraction == 0.9)
        // … and the small widget still leads with whichever is tightest.
        #expect(widget.accounts.first?.leadingWindow?.usedFraction == 0.9)
    }
}

@Suite("Widget account naming")
struct WidgetAccountNamingTests {
    /// Two accounts of the same provider must not render as two identical rows.
    @Test("Each account keeps its own name in the widget payload")
    func accountsKeepTheirNames() {
        let now = Date()
        let dashboard = DashboardSnapshot(
            generatedAt: now,
            usage: [
                UsageSnapshot(provider: .codex, accountID: "codex-personal", capturedAt: now),
                UsageSnapshot(provider: .codex, accountID: "codex-secondary", capturedAt: now),
            ],
            statuses: [
                ProviderStatus(
                    accountID: "codex-personal", provider: .codex,
                    displayName: "Codex · Personal", lastSuccessAt: now, lastAttemptAt: now
                ),
                ProviderStatus(
                    accountID: "codex-secondary", provider: .codex,
                    displayName: "Codex · Secondary", lastSuccessAt: now, lastAttemptAt: now
                ),
            ],
            bestFree: [:]
        )

        let widget = WidgetSnapshot(dashboard: dashboard, now: now)
        #expect(widget.accounts.map(\.displayName) == ["Codex · Personal", "Codex · Secondary"])
    }
}

@Suite("Widget account detail")
struct WidgetAccountDetailTests {
    /// An account with no quota windows (OpenRouter is pay-as-you-go) should say
    /// something true rather than render as 0% used.
    @Test("An account without windows falls back to its credits")
    func creditsBecomeTheDetail() {
        let now = Date()
        let dashboard = DashboardSnapshot(
            generatedAt: now,
            usage: [
                UsageSnapshot(
                    provider: .openRouter,
                    accountID: "openrouter",
                    capturedAt: now,
                    windows: [],
                    creditsRemainingUSD: Decimal(string: "8.7"),
                    planLabel: "Paid key"
                )
            ],
            statuses: [],
            bestFree: [:],
            freeModelCount: 22
        )

        let widget = WidgetSnapshot(dashboard: dashboard, now: now)
        let account = widget.accounts.first

        #expect(account?.detail == "$8.70 left")
        #expect(account?.shortWindow == nil)
        #expect(widget.freeModelCount == 22)
    }

    /// With no benchmark source there is no "smartest free model" to name, so the
    /// widget must not imply one exists.
    @Test("No benchmarks means no best-free claim")
    func noBenchmarksMeansNoBestFree() {
        let widget = WidgetSnapshot(
            dashboard: DashboardSnapshot(
                generatedAt: Date(), usage: [], statuses: [], bestFree: [:], freeModelCount: 22
            )
        )

        #expect(widget.bestFree.isEmpty)
        #expect(widget.freeModelCount == 22)
    }
}

@Suite("Cached credential")
struct CachedCredentialTests {
    /// Each Keychain read prompts on an ad-hoc signed build, so repeated reads
    /// must not reach the Keychain repeatedly.
    @Test("The secret is loaded once, however many times it is read")
    func loadsOnce() async throws {
        let loads = Counter()
        let credential = CachedCredential {
            await loads.increment()
            return "secret"
        }

        for _ in 0..<5 {
            #expect(try await credential.value() == "secret")
        }

        #expect(await loads.count == 1)
    }

    @Test("Invalidating forces the next read to go back to the source")
    func invalidateForcesReload() async throws {
        let loads = Counter()
        let credential = CachedCredential {
            await loads.increment()
            return "secret"
        }

        _ = try await credential.value()
        await credential.invalidate()
        _ = try await credential.value()

        #expect(await loads.count == 2)
    }

    /// A missing secret is cached too: absence is an answer, and re-asking would
    /// prompt again for nothing.
    @Test("A missing secret is not re-read on every call")
    func missingSecretIsCached() async throws {
        let loads = Counter()
        let credential = CachedCredential {
            await loads.increment()
            return nil
        }

        _ = try await credential.value()
        _ = try await credential.value()

        #expect(await loads.count == 1)
    }
}

private actor Counter {
    private(set) var count = 0
    func increment() { count += 1 }
}
