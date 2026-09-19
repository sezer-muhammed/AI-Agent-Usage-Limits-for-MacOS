import Foundation

public enum BenchmarkSource: String, Codable, Sendable {
    /// Metadata that came with the provider's own catalog response.
    case providerCatalog
    /// Artificial Analysis indices, as carried by the OpenRouter catalog.
    case artificialAnalysis
    /// A published benchmark feed — measured numbers from a named evaluation.
    case externalFeed
    /// Values bundled with the app build.
    case bundled
    /// Scores a language model produced. These are estimates, not measurements,
    /// and must be labelled as such wherever they are shown.
    case languageModelEstimate
    case unknown

    /// True when the numbers were not measured by running an evaluation.
    public var isEstimate: Bool { self == .languageModelEstimate }

    public var displayName: String {
        switch self {
        case .providerCatalog: "Provider catalog"
        case .artificialAnalysis: "Artificial Analysis"
        case .externalFeed: "Benchmark feed"
        case .bundled: "Bundled"
        case .languageModelEstimate: "Estimated"
        case .unknown: "Unknown source"
        }
    }
}

/// Separate benchmark dimensions. Deliberately not collapsed into one score:
/// the spec forbids an unexplained composite.
public struct ModelBenchmark: Codable, Sendable, Hashable {
    public let intelligence: Double?
    public let coding: Double?
    public let agentic: Double?

    public let source: BenchmarkSource
    public let capturedAt: Date

    public init(
        intelligence: Double?,
        coding: Double?,
        agentic: Double?,
        source: BenchmarkSource,
        capturedAt: Date
    ) {
        self.intelligence = intelligence
        self.coding = coding
        self.agentic = agentic
        self.source = source
        self.capturedAt = capturedAt
    }

    public var isEmpty: Bool { intelligence == nil && coding == nil && agentic == nil }
}
