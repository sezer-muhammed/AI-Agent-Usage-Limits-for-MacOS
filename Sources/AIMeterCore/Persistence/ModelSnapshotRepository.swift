import Foundation

/// Model catalog state plus the history that powers NEW / ↑2 / ↓ indicators.
public struct ModelSnapshotRepository: ModelSnapshotRepositoryProtocol {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func record(models: [AIModel], capturedAt: Date) async throws {
        for model in models {
            // first_seen_at is preserved on conflict so "NEW" stays meaningful.
            try await database.run(
                """
                INSERT INTO models
                    (canonical_id, provider_model_id, provider, source_provider, display_name,
                     context_length, is_free, input_price, output_price, modalities,
                     first_seen_at, last_seen_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (source_provider, provider_model_id) DO UPDATE SET
                    canonical_id = excluded.canonical_id,
                    display_name = excluded.display_name,
                    context_length = excluded.context_length,
                    is_free = excluded.is_free,
                    input_price = excluded.input_price,
                    output_price = excluded.output_price,
                    modalities = excluded.modalities,
                    last_seen_at = excluded.last_seen_at
                """,
                [
                    .text(model.canonicalID.rawValue),
                    .text(model.id),
                    .text(model.provider),
                    .text(model.sourceProviderID),
                    .text(model.displayName),
                    model.contextLength.map { .integer(Int64($0)) } ?? .null,
                    .integer(model.isFreeVariant ? 1 : 0),
                    model.inputPricePerMillion.map { .text("\($0)") } ?? .null,
                    model.outputPricePerMillion.map { .text("\($0)") } ?? .null,
                    .text(model.supportedModalities.joined(separator: ",")),
                    .real(capturedAt.timeIntervalSince1970),
                    .real(capturedAt.timeIntervalSince1970),
                ]
            )

            if let benchmark = model.benchmark, !benchmark.isEmpty {
                try await database.run(
                    """
                    INSERT INTO model_benchmark_snapshots
                        (canonical_id, captured_at, intelligence, coding, agentic, source)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    [
                        .text(model.canonicalID.rawValue),
                        .real(benchmark.capturedAt.timeIntervalSince1970),
                        benchmark.intelligence.map { .real($0) } ?? .null,
                        benchmark.coding.map { .real($0) } ?? .null,
                        benchmark.agentic.map { .real($0) } ?? .null,
                        .text(benchmark.source.rawValue),
                    ]
                )
            }

            if let availability = model.availability {
                try await database.run(
                    """
                    INSERT INTO model_availability_snapshots
                        (canonical_id, captured_at, availability_percentage, window_description)
                    VALUES (?, ?, ?, ?)
                    """,
                    [
                        .text(model.canonicalID.rawValue),
                        .real(availability.capturedAt.timeIntervalSince1970),
                        availability.percentage.map { .real($0) } ?? .null,
                        availability.sampleWindowDescription.map { .text($0) } ?? .null,
                    ]
                )
            }
        }
    }

    public func latestModels() async throws -> [AIModel] {
        try await database.query(
            """
            SELECT canonical_id, provider_model_id, provider, source_provider, display_name,
                   context_length, is_free, input_price, output_price, modalities
            FROM models ORDER BY display_name
            """
        ) { row in
            AIModel(
                id: row.string(1) ?? "",
                canonicalID: CanonicalModelID(row.string(0) ?? ""),
                displayName: row.string(4) ?? "",
                provider: row.string(2) ?? "",
                sourceProviderID: row.string(3) ?? "",
                contextLength: row.int(5).map(Int.init),
                inputPricePerMillion: row.decimal(7),
                outputPricePerMillion: row.decimal(8),
                isFreeVariant: (row.int(6) ?? 0) == 1,
                supportedModalities: (row.string(9) ?? "")
                    .split(separator: ",").map(String.init)
            )
        }
    }

    public func recordRanks(
        _ ranks: [RankingCategory: [CanonicalModelID]],
        capturedAt: Date
    ) async throws {
        for (category, ordered) in ranks {
            for (index, canonicalID) in ordered.enumerated() {
                try await database.run(
                    """
                    INSERT INTO model_rank_snapshots (captured_at, category, canonical_id, rank)
                    VALUES (?, ?, ?, ?)
                    """,
                    [
                        .real(capturedAt.timeIntervalSince1970),
                        .text(category.rawValue),
                        .text(canonicalID.rawValue),
                        .integer(Int64(index + 1)),
                    ]
                )
            }
        }
    }

    public func latestRanks() async throws -> [RankingCategory: [CanonicalModelID]] {
        var result: [RankingCategory: [CanonicalModelID]] = [:]

        for category in RankingCategory.allCases {
            guard
                let latestCapture = try await database.query(
                    "SELECT MAX(captured_at) FROM model_rank_snapshots WHERE category = ?",
                    [.text(category.rawValue)]
                , decode: { $0.double(0) }).first ?? nil
            else { continue }

            let ordered = try await database.query(
                """
                SELECT canonical_id FROM model_rank_snapshots
                WHERE category = ? AND captured_at = ? ORDER BY rank ASC
                """,
                [.text(category.rawValue), .real(latestCapture)]
            ) { CanonicalModelID($0.string(0) ?? "") }

            if !ordered.isEmpty { result[category] = ordered }
        }

        return result
    }
}
