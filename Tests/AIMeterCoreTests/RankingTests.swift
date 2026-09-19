import Foundation
import Testing

@testable import AIMeterCore

private func model(
    id: String,
    free: Bool,
    intelligence: Double? = nil,
    coding: Double? = nil,
    agentic: Double? = nil,
    availability: Double? = nil
) -> AIModel {
    AIModel(
        id: id,
        canonicalID: CanonicalModelID(id),
        displayName: id,
        provider: "vendor",
        sourceProviderID: "openrouter",
        contextLength: 128_000,
        inputPricePerMillion: nil,
        outputPricePerMillion: nil,
        isFreeVariant: free,
        supportedModalities: ["text"],
        benchmark: intelligence == nil && coding == nil && agentic == nil
            ? nil
            : ModelBenchmark(
                intelligence: intelligence,
                coding: coding,
                agentic: agentic,
                source: .bundled,
                capturedAt: Date()
            ),
        availability: availability.map {
            ModelAvailability(percentage: $0, capturedAt: Date())
        }
    )
}

@Suite("Model ranking")
struct RankingTests {
    let engine = ModelRankingEngine()

    @Test("Each category sorts by its own metric, not a composite")
    func categoriesAreIndependent() {
        let models = [
            model(id: "smart", free: true, intelligence: 90, coding: 10, agentic: 10),
            model(id: "coder", free: true, intelligence: 10, coding: 90, agentic: 10),
            model(id: "agent", free: true, intelligence: 10, coding: 10, agentic: 90),
        ]

        #expect(engine.bestGeneralFree(models)?.id == "smart")
        #expect(engine.bestCodingFree(models)?.id == "coder")
        #expect(engine.bestAgenticFree(models)?.id == "agent")
    }

    @Test("Paid models never appear in a free ranking")
    func paidModelsExcluded() {
        let models = [
            model(id: "paid-genius", free: false, intelligence: 99),
            model(id: "free-ok", free: true, intelligence: 40),
        ]

        #expect(engine.bestGeneralFree(models)?.id == "free-ok")
    }

    @Test("A model with no benchmark cannot be ranked, but is not invented a score")
    func unbenchmarkedModelsAreNotRanked() {
        let models = [model(id: "unknown", free: true)]

        #expect(engine.rank(models, category: .general).isEmpty)
        #expect(engine.bestGeneralFree(models) == nil)
    }

    @Test("Reliability ranks on availability and applies its floor")
    func reliabilityUsesAvailability() {
        let models = [
            model(id: "brilliant-but-flaky", free: true, intelligence: 95, availability: 71),
            model(id: "solid", free: true, intelligence: 40, availability: 99.6),
        ]

        #expect(engine.bestReliableFree(models)?.id == "solid")
        #expect(engine.rank(models, category: .reliable).count == 1)
    }

    @Test("A flaky model still ranks on intelligence — reliability is shown, not hidden")
    func flakyModelStillRanksOnIntelligence() {
        let models = [
            model(id: "brilliant-but-flaky", free: true, intelligence: 95, availability: 71),
            model(id: "solid", free: true, intelligence: 40, availability: 99.6),
        ]

        let best = engine.bestGeneralFree(models)
        #expect(best?.id == "brilliant-but-flaky")
        #expect(best?.availability?.percentage == 71)
    }
}

@Suite("Canonical model IDs")
struct CanonicalizationTests {
    let canonicalizer = ModelCanonicalizer()

    @Test("Free variants and paid variants share one identity")
    func freeVariantMapsToSameCanonicalID() {
        let free = canonicalizer.canonicalID(forProviderModelID: "vendor/model-x:free")
        let paid = canonicalizer.canonicalID(forProviderModelID: "vendor/model-x")

        #expect(free == paid)
    }

    @Test("A trailing release date is not a different model")
    func releaseDateStripped() {
        #expect(
            canonicalizer.canonicalID(forProviderModelID: "claude-opus-4-6-20260115")
                == canonicalizer.canonicalID(forProviderModelID: "claude-opus-4-6")
        )
    }

    @Test("Pointer suffixes resolve to the underlying model")
    func latestSuffixStripped() {
        #expect(
            canonicalizer.canonicalID(forProviderModelID: "vendor/model-y-latest")
                == CanonicalModelID("model-y")
        )
    }

    @Test("Vendor is read from the namespace")
    func vendorExtracted() {
        #expect(canonicalizer.vendor(forProviderModelID: "vendor/model-x:free") == "vendor")
        #expect(canonicalizer.vendor(forProviderModelID: "bare-model") == "unknown")
    }
}
