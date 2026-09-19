import AIMeterCore
import Foundation

/// Normalizes the OpenRouter catalog into `AIModel`.
public struct OpenRouterModelsAdapter: ModelCatalogProvider {
    public let providerID: Provider.ID = Provider.openRouter.id

    private let client: OpenRouterClient
    private let canonicalizer: ModelCanonicalizer

    public init(client: OpenRouterClient, canonicalizer: ModelCanonicalizer = ModelCanonicalizer()) {
        self.client = client
        self.canonicalizer = canonicalizer
    }

    public func fetchModels() async throws -> [AIModel] {
        try await client.models().map(normalize)
    }

    private func normalize(_ dto: OpenRouterDTO.Model) -> AIModel {
        let promptPrice = dto.pricing?.prompt.flatMap { Decimal(string: $0) }
        let completionPrice = dto.pricing?.completion.flatMap { Decimal(string: $0) }

        return AIModel(
            id: dto.id,
            canonicalID: canonicalizer.canonicalID(forProviderModelID: dto.canonicalSlug ?? dto.id),
            displayName: dto.name ?? dto.id,
            provider: canonicalizer.vendor(forProviderModelID: dto.id),
            sourceProviderID: providerID,
            contextLength: dto.contextLength ?? dto.topProvider?.contextLength,
            // API prices are per token; the UI talks in per-million.
            inputPricePerMillion: promptPrice.map { $0 * 1_000_000 },
            outputPricePerMillion: completionPrice.map { $0 * 1_000_000 },
            // A real OpenRouter free variant, not merely a zero-priced row.
            isFreeVariant: Self.isFreeVariant(dto),
            supportedModalities: dto.architecture?.inputModalities
                ?? dto.architecture?.modality.map { [$0] }
                ?? []
        )
    }

    /// Free variants are the `:free` endpoints. A zero price alone is not enough:
    /// promotional zero-priced paid endpoints exist and behave differently.
    static func isFreeVariant(_ dto: OpenRouterDTO.Model) -> Bool {
        dto.id.hasSuffix(":free")
    }
}
