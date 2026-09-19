import Foundation

/// Diffs two catalog states into the handful of changes worth showing.
///
/// Thresholds exist so benchmark jitter and rank churn do not fill the
/// "Recent Changes" list with noise.
public struct ModelChangeDetector: Sendable {
    public struct Thresholds: Sendable {
        public var minimumBenchmarkDelta: Double
        public var minimumAvailabilityDelta: Double
        /// Rank moves outside the visible top N are not interesting.
        public var trackedRankDepth: Int

        public init(
            minimumBenchmarkDelta: Double = 0.5,
            minimumAvailabilityDelta: Double = 2.0,
            trackedRankDepth: Int = 10
        ) {
            self.minimumBenchmarkDelta = minimumBenchmarkDelta
            self.minimumAvailabilityDelta = minimumAvailabilityDelta
            self.trackedRankDepth = trackedRankDepth
        }
    }

    private let thresholds: Thresholds

    public init(thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
    }

    public func changes(
        previous: [AIModel],
        current: [AIModel],
        previousRanks: [RankingCategory: [CanonicalModelID]] = [:],
        currentRanks: [RankingCategory: [CanonicalModelID]] = [:],
        detectedAt: Date = Date()
    ) -> [ModelChangeEvent] {
        var events: [ModelChangeEvent] = []

        let previousByID = Dictionary(previous.map { ($0.canonicalID, $0) }, uniquingKeysWith: { a, _ in a })
        let currentByID = Dictionary(current.map { ($0.canonicalID, $0) }, uniquingKeysWith: { a, _ in a })

        for (canonicalID, model) in currentByID where previousByID[canonicalID] == nil {
            events.append(
                ModelChangeEvent(
                    canonicalID: canonicalID,
                    displayName: model.displayName,
                    change: .appeared,
                    detectedAt: detectedAt
                )
            )
        }

        for (canonicalID, model) in previousByID where currentByID[canonicalID] == nil {
            events.append(
                ModelChangeEvent(
                    canonicalID: canonicalID,
                    displayName: model.displayName,
                    change: .disappeared,
                    detectedAt: detectedAt
                )
            )
        }

        for (canonicalID, model) in currentByID {
            guard let old = previousByID[canonicalID] else { continue }

            for dimension in BenchmarkDimension.allCases {
                let before = old.benchmark.flatMap { dimension.value(in: $0) }
                let after = model.benchmark.flatMap { dimension.value(in: $0) }
                guard let before, let after else { continue }
                guard abs(after - before) >= thresholds.minimumBenchmarkDelta else { continue }

                events.append(
                    ModelChangeEvent(
                        canonicalID: canonicalID,
                        displayName: model.displayName,
                        change: .benchmarkChanged(dimension: dimension, from: before, to: after),
                        detectedAt: detectedAt
                    )
                )
            }

            let beforeAvailability = old.availability?.percentage
            let afterAvailability = model.availability?.percentage
            if let beforeAvailability, let afterAvailability,
                abs(afterAvailability - beforeAvailability) >= thresholds.minimumAvailabilityDelta
            {
                events.append(
                    ModelChangeEvent(
                        canonicalID: canonicalID,
                        displayName: model.displayName,
                        change: .availabilityChanged(
                            from: beforeAvailability,
                            to: afterAvailability
                        ),
                        detectedAt: detectedAt
                    )
                )
            }
        }

        for (category, ordered) in currentRanks {
            guard let previousOrdered = previousRanks[category] else { continue }

            for (index, canonicalID) in ordered.prefix(thresholds.trackedRankDepth).enumerated() {
                guard let oldIndex = previousOrdered.firstIndex(of: canonicalID) else { continue }
                guard oldIndex != index else { continue }

                events.append(
                    ModelChangeEvent(
                        canonicalID: canonicalID,
                        displayName: currentByID[canonicalID]?.displayName ?? canonicalID.rawValue,
                        change: .rankChanged(category: category, from: oldIndex + 1, to: index + 1),
                        detectedAt: detectedAt
                    )
                )
            }
        }

        return events
    }
}
