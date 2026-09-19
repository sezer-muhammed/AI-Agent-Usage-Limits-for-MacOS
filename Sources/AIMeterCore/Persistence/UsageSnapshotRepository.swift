import Foundation

/// Usage history, stored as normalized rows rather than raw provider payloads.
public struct UsageSnapshotRepository: UsageSnapshotRepositoryProtocol {
    private let database: Database
    private let providersByID: @Sendable (String) -> Provider

    public init(
        database: Database,
        providerResolver: @escaping @Sendable (String) -> Provider = { id in
            Provider(id: id, displayName: id.capitalized)
        }
    ) {
        self.database = database
        self.providersByID = providerResolver
    }

    public func record(_ snapshot: UsageSnapshot) async throws {
        let snapshotID = try await database.run(
            """
            INSERT INTO usage_snapshots
                (account_id, provider, captured_at, spend_today, spend_week, spend_month,
                 credits_remaining, active_model_id, plan_label)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(snapshot.accountID),
                .text(snapshot.provider.id),
                .real(snapshot.capturedAt.timeIntervalSince1970),
                snapshot.spendTodayUSD.map { .text("\($0)") } ?? .null,
                snapshot.spendWeekUSD.map { .text("\($0)") } ?? .null,
                snapshot.spendMonthUSD.map { .text("\($0)") } ?? .null,
                snapshot.creditsRemainingUSD.map { .text("\($0)") } ?? .null,
                snapshot.activeModelID.map { .text($0) } ?? .null,
                snapshot.planLabel.map { .text($0) } ?? .null,
            ]
        )

        for window in snapshot.windows {
            try await database.run(
                """
                INSERT INTO rate_limit_snapshots
                    (usage_snapshot_id, window_id, kind, label, used_fraction,
                     remaining_fraction, resets_at, duration_minutes)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .integer(snapshotID),
                    .text(window.id),
                    .text(window.kind.rawValue),
                    .text(window.label),
                    window.usedFraction.map { .real($0) } ?? .null,
                    window.remainingFraction.map { .real($0) } ?? .null,
                    window.resetsAt.map { .real($0.timeIntervalSince1970) } ?? .null,
                    window.durationMinutes.map { .integer(Int64($0)) } ?? .null,
                ]
            )
        }
    }

    public func latest(accountID: String) async throws -> UsageSnapshot? {
        try await load(
            where: "account_id = ? ORDER BY captured_at DESC LIMIT 1",
            parameters: [.text(accountID)]
        ).first
    }

    public func latestAll() async throws -> [UsageSnapshot] {
        let accountIDs = try await database.query("SELECT DISTINCT account_id FROM usage_snapshots") {
            $0.string(0)
        }.compactMap { $0 }

        var results: [UsageSnapshot] = []
        for accountID in accountIDs {
            if let snapshot = try await latest(accountID: accountID) { results.append(snapshot) }
        }
        return results
    }

    public func history(accountID: String, since: Date) async throws -> [UsageSnapshot] {
        try await load(
            where: "account_id = ? AND captured_at >= ? ORDER BY captured_at ASC",
            parameters: [.text(accountID), .real(since.timeIntervalSince1970)]
        )
    }

    /// Cheap deferred cleanup: the database must not grow forever.
    public func prune(rawOlderThan cutoff: Date) async throws {
        try await database.run(
            "DELETE FROM usage_snapshots WHERE captured_at < ?",
            [.real(cutoff.timeIntervalSince1970)]
        )
        try await database.run(
            """
            DELETE FROM rate_limit_snapshots
            WHERE usage_snapshot_id NOT IN (SELECT id FROM usage_snapshots)
            """
        )
    }

    private func load(where clause: String, parameters: [Database.Value]) async throws
        -> [UsageSnapshot]
    {
        struct RawSnapshot: Sendable {
            let id: Int64
            let accountID: String
            let providerID: String
            let capturedAt: Date
            let spendToday: Decimal?
            let spendWeek: Decimal?
            let spendMonth: Decimal?
            let credits: Decimal?
            let activeModelID: String?
            let planLabel: String?
        }

        let raws = try await database.query(
            """
            SELECT id, account_id, provider, captured_at, spend_today, spend_week,
                   spend_month, credits_remaining, active_model_id, plan_label
            FROM usage_snapshots WHERE \(clause)
            """,
            parameters
        ) { row in
            RawSnapshot(
                id: row.int(0) ?? 0,
                accountID: row.string(1) ?? "",
                providerID: row.string(2) ?? "",
                capturedAt: row.date(3) ?? .distantPast,
                spendToday: row.decimal(4),
                spendWeek: row.decimal(5),
                spendMonth: row.decimal(6),
                credits: row.decimal(7),
                activeModelID: row.string(8),
                planLabel: row.string(9)
            )
        }

        var snapshots: [UsageSnapshot] = []
        for raw in raws {
            let windows = try await database.query(
                """
                SELECT window_id, kind, label, used_fraction, remaining_fraction,
                       resets_at, duration_minutes
                FROM rate_limit_snapshots WHERE usage_snapshot_id = ?
                """,
                [.integer(raw.id)]
            ) { row in
                RateLimitWindow(
                    id: row.string(0) ?? "",
                    kind: RateLimitWindow.Kind(rawValue: row.string(1) ?? "") ?? .custom,
                    usedFraction: row.double(3),
                    remainingFraction: row.double(4),
                    resetsAt: row.date(5),
                    durationMinutes: row.int(6).map(Int.init),
                    label: row.string(2) ?? ""
                )
            }

            snapshots.append(
                UsageSnapshot(
                    provider: providersByID(raw.providerID),
                    accountID: raw.accountID,
                    capturedAt: raw.capturedAt,
                    windows: windows,
                    spendTodayUSD: raw.spendToday,
                    spendWeekUSD: raw.spendWeek,
                    spendMonthUSD: raw.spendMonth,
                    creditsRemainingUSD: raw.credits,
                    activeModelID: raw.activeModelID,
                    planLabel: raw.planLabel
                )
            )
        }
        return snapshots
    }
}
