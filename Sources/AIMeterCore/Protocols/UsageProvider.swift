import Foundation

/// Anything that can report quota/spend for one account.
public protocol UsageProvider: Sendable {
    var providerID: Provider.ID { get }
    var accountID: String { get }

    func fetchUsage() async throws -> UsageSnapshot
}

/// Anything that can list models. Separate from `UsageProvider` because some
/// accounts expose one and not the other.
public protocol ModelCatalogProvider: Sendable {
    var providerID: Provider.ID { get }

    func fetchModels() async throws -> [AIModel]
}

/// A source of benchmark scores, joined onto the catalog by canonical model ID.
public protocol BenchmarkProvider: Sendable {
    func benchmarks() async throws -> [CanonicalModelID: ModelBenchmark]
}

/// A source of endpoint reliability numbers.
public protocol AvailabilityProvider: Sendable {
    func availability() async throws -> [CanonicalModelID: ModelAvailability]
}
