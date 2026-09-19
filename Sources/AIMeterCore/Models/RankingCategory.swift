import Foundation

/// The independently computed "best free" lists. No universal "best model".
public enum RankingCategory: String, Codable, Sendable, CaseIterable {
    case general
    case coding
    case agentic
    case reliable

    public var displayName: String {
        switch self {
        case .general: "Best General Free"
        case .coding: "Best Coding Free"
        case .agentic: "Best Agentic Free"
        case .reliable: "Best Reliable Free"
        }
    }
}

public enum BenchmarkDimension: String, Codable, Sendable, CaseIterable {
    case intelligence
    case coding
    case agentic

    public func value(in benchmark: ModelBenchmark) -> Double? {
        switch self {
        case .intelligence: benchmark.intelligence
        case .coding: benchmark.coding
        case .agentic: benchmark.agentic
        }
    }
}
