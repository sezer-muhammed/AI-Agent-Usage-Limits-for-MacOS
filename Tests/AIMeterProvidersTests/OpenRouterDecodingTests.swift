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
