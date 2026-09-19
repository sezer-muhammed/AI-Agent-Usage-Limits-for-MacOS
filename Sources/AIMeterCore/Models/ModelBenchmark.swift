import Foundation

public enum BenchmarkSource: String, Codable, Sendable {
    /// Metadata that came with the provider's own catalog response.
    case providerCatalog
    /// A benchmark feed the user configured.
    case externalFeed
    /// Values bundled with the app build.
    case bundled
    case unknown
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
