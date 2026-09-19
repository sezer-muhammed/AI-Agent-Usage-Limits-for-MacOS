import Foundation

/// Produces the "best free" lists.
///
/// Each category sorts by one stated metric. There is no hidden composite score,
/// and no model is described as universally best.
public struct ModelRankingEngine: Sendable {
    public struct Options: Sendable {
        /// Reliability floor applied to the `reliable` category only.
        public var minimumAvailabilityForReliable: Double
        /// Models without any benchmark still appear in the catalog, but cannot
        /// be ranked in a benchmark category.
        public var requiresBenchmark: Bool

        public init(minimumAvailabilityForReliable: Double = 95, requiresBenchmark: Bool = true) {
            self.minimumAvailabilityForReliable = minimumAvailabilityForReliable
            self.requiresBenchmark = requiresBenchmark
        }
    }

    private let options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    public func rank(_ models: [AIModel], category: RankingCategory) -> [AIModel] {
        let free = models.filter(\.isFreeVariant)

        switch category {
        case .general:
            return sorted(free, by: .intelligence)
        case .coding:
            return sorted(free, by: .coding)
        case .agentic:
            return sorted(free, by: .agentic)
        case .reliable:
            // Reliability is an availability question first; intelligence only
            // breaks ties among models that clear the floor.
            let eligible = free.filter {
                ($0.availability?.percentage ?? 0) >= options.minimumAvailabilityForReliable
            }
            return eligible.sorted { lhs, rhs in
                let lhsAvailability = lhs.availability?.percentage ?? 0
                let rhsAvailability = rhs.availability?.percentage ?? 0
                if lhsAvailability != rhsAvailability { return lhsAvailability > rhsAvailability }
                return (lhs.benchmark?.intelligence ?? 0) > (rhs.benchmark?.intelligence ?? 0)
            }
        }
    }

    public func bestGeneralFree(_ models: [AIModel]) -> AIModel? { rank(models, category: .general).first }
    public func bestCodingFree(_ models: [AIModel]) -> AIModel? { rank(models, category: .coding).first }
    public func bestAgenticFree(_ models: [AIModel]) -> AIModel? { rank(models, category: .agentic).first }
    public func bestReliableFree(_ models: [AIModel]) -> AIModel? { rank(models, category: .reliable).first }

    public func bestFree(_ models: [AIModel]) -> [RankingCategory: AIModel] {
        var result: [RankingCategory: AIModel] = [:]
        for category in RankingCategory.allCases {
            if let best = rank(models, category: category).first { result[category] = best }
        }
        return result
    }

    private func sorted(_ models: [AIModel], by dimension: BenchmarkDimension) -> [AIModel] {
        models
            .filter { model in
                guard options.requiresBenchmark else { return true }
                guard let benchmark = model.benchmark else { return false }
                return dimension.value(in: benchmark) != nil
            }
            .sorted { lhs, rhs in
                let lhsScore = lhs.benchmark.flatMap { dimension.value(in: $0) } ?? -.infinity
                let rhsScore = rhs.benchmark.flatMap { dimension.value(in: $0) } ?? -.infinity
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhs.displayName < rhs.displayName
            }
    }
}
