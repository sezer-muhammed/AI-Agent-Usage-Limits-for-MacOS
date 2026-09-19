import AIMeterCore
import Foundation
import Testing

@testable import AIMeterProviders

@Suite("OpenRouter decoding")
struct OpenRouterDecodingTests {
    @Test("The model catalog decodes")
    func modelsDecode() throws {
        let list = try JSONDecoder().decode(
            OpenRouterDTO.ModelList.self,
            from: Fixture.data("OpenRouter/models.json")
        )

        #expect(list.data.count == 3)
        #expect(list.data.first?.contextLength == 262_144)
        #expect(list.data.first?.architecture?.inputModalities == ["text"])
    }

    @Test("Only a :free endpoint counts as a free variant")
    func freeVariantDetection() throws {
        let list = try JSONDecoder().decode(
            OpenRouterDTO.ModelList.self,
            from: Fixture.data("OpenRouter/models.json")
        )

        let free = list.data.filter(OpenRouterModelsAdapter.isFreeVariant)

        #expect(free.map(\.id) == ["examplelab/reference-chat:free"])
        // A zero-priced non-":free" endpoint is deliberately not treated as free.
        #expect(!free.contains { $0.id == "othervendor/promo-model" })
    }

    @Test("Key usage decodes as dollars, never as a request count")
    func keyInfoDecodes() throws {
        let envelope = try JSONDecoder().decode(
            OpenRouterDTO.Envelope<OpenRouterDTO.KeyInfo>.self,
            from: Fixture.data("OpenRouter/key.json")
        )

        #expect(envelope.data.usage == 2.5)
        #expect(envelope.data.usageDaily == 0.25)
        #expect(envelope.data.limit == 10.0)
        #expect(envelope.data.isFreeTier == false)
    }

    @Test("A free-tier key with no limit decodes without inventing values")
    func freeTierKeyDecodes() throws {
        let envelope = try JSONDecoder().decode(
            OpenRouterDTO.Envelope<OpenRouterDTO.KeyInfo>.self,
            from: Fixture.data("OpenRouter/key-free-tier.json")
        )

        #expect(envelope.data.isFreeTier == true)
        #expect(envelope.data.limit == nil)
        #expect(envelope.data.limitRemaining == nil)
        // No daily/weekly spend was reported, so none is reported onward.
        #expect(envelope.data.usageDaily == nil)
    }
}

@Suite("OpenRouter usage normalization")
struct OpenRouterUsageAdapterTests {
    /// OpenRouter returns a truncated copy of the API key in `label`
    /// ("sk-or-v1-2a1...260"). Nothing derived from it may reach a snapshot,
    /// because snapshots are persisted and projected into the widget payload.
    @Test("A key fragment from the label never reaches the usage snapshot")
    func labelNeverLeaksIntoSnapshot() async throws {
        let payload = """
            {"data":{"label":"sk-or-v1-2a1...260","usage":0,"limit":10,
             "limit_remaining":10,"is_free_tier":false}}
            """

        let key = try JSONDecoder().decode(
            OpenRouterDTO.Envelope<OpenRouterDTO.KeyInfo>.self,
            from: Data(payload.utf8)
        ).data

        // The DTO still carries it …
        #expect(key.label == "sk-or-v1-2a1...260")

        let snapshot = UsageSnapshot(
            provider: .openRouter,
            accountID: "openrouter",
            capturedAt: Date(),
            planLabel: key.isFreeTier == true ? "Free tier" : "Paid key"
        )

        // … but nothing key-shaped survives into what gets stored.
        #expect(snapshot.planLabel == "Paid key")
        let encoded = try DateFormatting.makeEncoder().encode(snapshot)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains("sk-or"))
    }
}

@Suite("OpenRouter benchmarks")
struct OpenRouterBenchmarkTests {
    private func models() throws -> [OpenRouterDTO.Model] {
        try JSONDecoder().decode(
            OpenRouterDTO.ModelList.self,
            from: Fixture.data("OpenRouter/models.json")
        ).data
    }

    /// The catalog carries Artificial Analysis indices, so AI Meter needs no
    /// scoring of its own.
    @Test("Artificial Analysis indices decode into the three dimensions")
    func indicesDecode() throws {
        let captured = Date(timeIntervalSince1970: 1_800_000_000)
        let benchmark = try #require(
            OpenRouterModelsAdapter.benchmark(models()[0], capturedAt: captured)
        )

        #expect(benchmark.intelligence == 34.5)
        #expect(benchmark.coding == 69.1)
        #expect(benchmark.agentic == 41.7)
        #expect(benchmark.source == .artificialAnalysis)
        // Measured, so nothing may present it as an estimate.
        #expect(!benchmark.source.isEstimate)
    }

    @Test("A model without indices gets no benchmark rather than zeros")
    func missingIndicesStayMissing() throws {
        let all = try models()

        #expect(OpenRouterModelsAdapter.benchmark(all[1], capturedAt: Date()) == nil)
        // Present but empty benchmarks object: still nothing to show.
        #expect(OpenRouterModelsAdapter.benchmark(all[2], capturedAt: Date()) == nil)
    }

    @Test("Ranking uses the catalog's own scores")
    func rankingUsesCatalogScores() throws {
        let canonicalizer = ModelCanonicalizer()
        let captured = Date()

        let catalog = try models().map { dto in
            AIModel(
                id: dto.id,
                canonicalID: canonicalizer.canonicalID(forProviderModelID: dto.id),
                displayName: dto.name ?? dto.id,
                provider: canonicalizer.vendor(forProviderModelID: dto.id),
                sourceProviderID: Provider.openRouter.id,
                contextLength: dto.contextLength,
                inputPricePerMillion: nil,
                outputPricePerMillion: nil,
                isFreeVariant: OpenRouterModelsAdapter.isFreeVariant(dto),
                supportedModalities: [],
                benchmark: OpenRouterModelsAdapter.benchmark(dto, capturedAt: captured)
            )
        }

        let engine = ModelRankingEngine()
        #expect(engine.bestGeneralFree(catalog)?.id == "examplelab/reference-chat:free")
        #expect(engine.bestCodingFree(catalog)?.id == "examplelab/reference-chat:free")
        // No availability data in the catalog, so nothing can claim reliability.
        #expect(engine.bestReliableFree(catalog) == nil)
    }
}
