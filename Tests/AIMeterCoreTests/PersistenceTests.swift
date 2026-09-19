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
                    id: "claude", displayName: "Claude", primaryUsage: 0.72,
                    resetsAt: nil, isStale: false
                )
            ]
        )

        try await writer.write(snapshot)
        let loaded = try writer.read()

        #expect(loaded?.schemaVersion == WidgetSnapshot.schemaVersion)
        #expect(loaded?.accounts.first?.primaryUsage == 0.72)
        #expect(loaded?.bestFree["general"]?.name == "Fixture")
    }

    @Test("Projection from a dashboard carries no credentials, only usage")
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
        // The most-consumed window is what the widget leads with.
        #expect(widget.accounts.first?.primaryUsage == 0.9)
    }
}
