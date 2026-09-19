import Foundation

/// A model as AI Meter understands it, after provider DTOs have been normalized.
public struct AIModel: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let canonicalID: CanonicalModelID
    public let displayName: String

    /// Upstream vendor ("deepseek", "openai", …), not the account provider.
    public let provider: String
    /// Which AI Meter provider surfaced this model.
    public let sourceProviderID: Provider.ID

    public let contextLength: Int?

    public let inputPricePerMillion: Decimal?
    public let outputPricePerMillion: Decimal?

    /// True only for genuine free variants (e.g. an OpenRouter `:free` endpoint),
    /// not for every zero-priced row.
    public let isFreeVariant: Bool

    public let supportedModalities: [String]

    public let benchmark: ModelBenchmark?
    public let availability: ModelAvailability?

    /// When the provider published this model, when it says so. Drives "newest
    /// free model" and the NEW badge.
    public let createdAt: Date?

    public init(
        id: String,
        canonicalID: CanonicalModelID,
        displayName: String,
        provider: String,
        sourceProviderID: Provider.ID,
        contextLength: Int?,
        inputPricePerMillion: Decimal?,
        outputPricePerMillion: Decimal?,
        isFreeVariant: Bool,
        supportedModalities: [String],
        benchmark: ModelBenchmark? = nil,
        availability: ModelAvailability? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.canonicalID = canonicalID
        self.displayName = displayName
        self.provider = provider
        self.sourceProviderID = sourceProviderID
        self.contextLength = contextLength
        self.inputPricePerMillion = inputPricePerMillion
        self.outputPricePerMillion = outputPricePerMillion
        self.isFreeVariant = isFreeVariant
        self.supportedModalities = supportedModalities
        self.benchmark = benchmark
        self.availability = availability
        self.createdAt = createdAt
    }

    public func attaching(
        benchmark: ModelBenchmark?,
        availability: ModelAvailability? = nil
    ) -> AIModel {
        AIModel(
            id: id,
            canonicalID: canonicalID,
            displayName: displayName,
            provider: provider,
            sourceProviderID: sourceProviderID,
            contextLength: contextLength,
            inputPricePerMillion: inputPricePerMillion,
            outputPricePerMillion: outputPricePerMillion,
            isFreeVariant: isFreeVariant,
            supportedModalities: supportedModalities,
            benchmark: benchmark ?? self.benchmark,
            availability: availability ?? self.availability,
            createdAt: createdAt
        )
    }
}
