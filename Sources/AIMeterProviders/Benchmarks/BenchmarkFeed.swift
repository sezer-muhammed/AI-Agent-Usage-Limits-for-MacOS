import AIMeterCore
import Foundation

/// The on-disk benchmark feed.
///
/// AI Meter does not measure models itself, and no provider catalog carries
/// scores, so scores arrive through this file. Whoever writes it — a published
/// leaderboard export, a scheduled job, a hand-curated list — must say where the
/// numbers came from, because a model-produced estimate and a measured
/// evaluation cannot honestly be shown the same way.
public struct BenchmarkFeed: Codable, Sendable {
    public static let schemaVersion = 1
    public static let fileName = "benchmarks.json"

    public struct Entry: Codable, Sendable {
        /// Canonical model id, or any provider id — both are normalized on load.
        public let model: String
        public let intelligence: Double?
        public let coding: Double?
        public let agentic: Double?
        /// Endpoint reliability, when the feed tracks it.
        public let availability: Double?

        public init(
            model: String,
            intelligence: Double? = nil,
            coding: Double? = nil,
            agentic: Double? = nil,
            availability: Double? = nil
        ) {
            self.model = model
            self.intelligence = intelligence
            self.coding = coding
            self.agentic = agentic
            self.availability = availability
        }
    }

    public let schemaVersion: Int
    public let capturedAt: Date
    public let source: BenchmarkSource
    /// Free text naming the origin ("Artificial Analysis 2026-09", "claude-haiku-4-5").
    public let sourceDescription: String?
    public let entries: [Entry]

    public init(
        capturedAt: Date,
        source: BenchmarkSource,
        sourceDescription: String? = nil,
        entries: [Entry]
    ) {
        self.schemaVersion = Self.schemaVersion
        self.capturedAt = capturedAt
        self.source = source
        self.sourceDescription = sourceDescription
        self.entries = entries
    }

    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let base =
            (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ))
            ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")

        return
            base
            .appendingPathComponent("AIMeter", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}

/// Reads the feed and exposes it as benchmarks and availability keyed by
/// canonical model id.
public struct FileBenchmarkProvider: BenchmarkProvider, AvailabilityProvider {
    private let url: URL
    private let canonicalizer: ModelCanonicalizer

    public init(
        url: URL = BenchmarkFeed.defaultURL(),
        canonicalizer: ModelCanonicalizer = ModelCanonicalizer()
    ) {
        self.url = url
        self.canonicalizer = canonicalizer
    }

    public var feedURL: URL { url }

    public var isConfigured: Bool { FileManager.default.fileExists(atPath: url.path) }

    public func load() throws -> BenchmarkFeed {
        guard let data = try? Data(contentsOf: url) else {
            throw ProviderError.configurationMissing("benchmark feed")
        }
        do {
            return try DateFormatting.makeDecoder().decode(BenchmarkFeed.self, from: data)
        } catch {
            throw ProviderError.malformedResponse("benchmark feed")
        }
    }

    public func benchmarks() async throws -> [CanonicalModelID: ModelBenchmark] {
        let feed = try load()

        var result: [CanonicalModelID: ModelBenchmark] = [:]
        for entry in feed.entries {
            // An entry with no scores at all would otherwise mask a real one.
            guard entry.intelligence != nil || entry.coding != nil || entry.agentic != nil else {
                continue
            }

            result[canonicalizer.canonicalID(forProviderModelID: entry.model)] = ModelBenchmark(
                intelligence: entry.intelligence,
                coding: entry.coding,
                agentic: entry.agentic,
                source: feed.source,
                capturedAt: feed.capturedAt
            )
        }
        return result
    }

    public func availability() async throws -> [CanonicalModelID: ModelAvailability] {
        let feed = try load()

        var result: [CanonicalModelID: ModelAvailability] = [:]
        for entry in feed.entries {
            guard let percentage = entry.availability else { continue }
            result[canonicalizer.canonicalID(forProviderModelID: entry.model)] = ModelAvailability(
                percentage: percentage,
                capturedAt: feed.capturedAt,
                sampleWindowDescription: feed.sourceDescription
            )
        }
        return result
    }
}
