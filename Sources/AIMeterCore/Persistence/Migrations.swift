import Foundation

/// Ordered, append-only schema migrations.
///
/// Never edit a shipped migration — add a new one. `user_version` records how
/// far a database has been migrated.
public enum Migrations {
    public static let all: [String] = [
        // v1 — accounts, usage history, model catalog history.
        """
        CREATE TABLE IF NOT EXISTS accounts (
            id           TEXT PRIMARY KEY,
            provider     TEXT NOT NULL,
            display_name TEXT NOT NULL,
            profile_path TEXT,
            created_at   REAL NOT NULL,
            updated_at   REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS usage_snapshots (
            id                  INTEGER PRIMARY KEY AUTOINCREMENT,
            account_id          TEXT NOT NULL,
            provider            TEXT NOT NULL,
            captured_at         REAL NOT NULL,
            spend_today         TEXT,
            spend_week          TEXT,
            spend_month         TEXT,
            credits_remaining   TEXT,
            active_model_id     TEXT,
            plan_label          TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_usage_account_time
            ON usage_snapshots (account_id, captured_at DESC);

        CREATE TABLE IF NOT EXISTS rate_limit_snapshots (
            id                 INTEGER PRIMARY KEY AUTOINCREMENT,
            usage_snapshot_id  INTEGER NOT NULL REFERENCES usage_snapshots(id) ON DELETE CASCADE,
            window_id          TEXT NOT NULL,
            kind               TEXT NOT NULL,
            label              TEXT NOT NULL,
            used_fraction      REAL,
            remaining_fraction REAL,
            resets_at          REAL,
            duration_minutes   INTEGER
        );
        CREATE INDEX IF NOT EXISTS idx_rate_limit_usage
            ON rate_limit_snapshots (usage_snapshot_id);

        CREATE TABLE IF NOT EXISTS models (
            canonical_id      TEXT NOT NULL,
            provider_model_id TEXT NOT NULL,
            provider          TEXT NOT NULL,
            source_provider   TEXT NOT NULL,
            display_name      TEXT NOT NULL,
            context_length    INTEGER,
            is_free           INTEGER NOT NULL,
            input_price       TEXT,
            output_price      TEXT,
            modalities        TEXT,
            first_seen_at     REAL NOT NULL,
            last_seen_at      REAL NOT NULL,
            PRIMARY KEY (source_provider, provider_model_id)
        );
        CREATE INDEX IF NOT EXISTS idx_models_canonical ON models (canonical_id);

        CREATE TABLE IF NOT EXISTS model_benchmark_snapshots (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            canonical_id      TEXT NOT NULL,
            captured_at       REAL NOT NULL,
            intelligence      REAL,
            coding            REAL,
            agentic           REAL,
            source            TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_benchmark_model_time
            ON model_benchmark_snapshots (canonical_id, captured_at DESC);

        CREATE TABLE IF NOT EXISTS model_availability_snapshots (
            id                     INTEGER PRIMARY KEY AUTOINCREMENT,
            canonical_id           TEXT NOT NULL,
            captured_at            REAL NOT NULL,
            availability_percentage REAL,
            window_description     TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_availability_model_time
            ON model_availability_snapshots (canonical_id, captured_at DESC);

        CREATE TABLE IF NOT EXISTS model_rank_snapshots (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            captured_at  REAL NOT NULL,
            category     TEXT NOT NULL,
            canonical_id TEXT NOT NULL,
            rank         INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_rank_category_time
            ON model_rank_snapshots (category, captured_at DESC);
        """
    ]

    public static func migrate(_ database: Database) async throws {
        let current = try await database.query("PRAGMA user_version") { row in
            Int(row.int(0) ?? 0)
        }.first ?? 0

        guard current < all.count else { return }

        for index in current..<all.count {
            try await database.execute(all[index])
            try await database.execute("PRAGMA user_version = \(index + 1)")
        }

        // WAL keeps readers (dashboard) off the writer's back without busy-waiting.
        try await database.execute("PRAGMA journal_mode = WAL")
        try await database.execute("PRAGMA foreign_keys = ON")
    }
}
