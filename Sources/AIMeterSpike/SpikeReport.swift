import AIMeterCore
import Foundation

/// The normalized debug payload the feasibility spike prints.
///
/// Shaped after section 86 of the specification. Every provider section reports
/// what it managed to read *and* what it could not, because proving a field is
/// unavailable is as much a result as reading it.
struct SpikeReport: Encodable {
    struct ProviderSection: Encodable {
        var status: String
        var detail: String?
        var planLabel: String?
        var windows: [Window]?
        var spendTodayUSD: String?
        var creditsRemainingUSD: String?
        var modelCount: Int?
        var sampleModels: [String]?
        var capturedAt: Date?
        var freshness: String?
        var unsupportedMethods: [String]?

        static func failed(_ error: any Error) -> ProviderSection {
            ProviderSection(
                status: "unavailable",
                detail: (error as? ProviderError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    struct Window: Encodable {
        let label: String
        let kind: String
        let usedPercentage: Double?
        let resetsAt: Date?
        let durationMinutes: Int?

        init(_ window: RateLimitWindow) {
            label = window.label
            kind = window.kind.rawValue
            usedPercentage = window.usedFraction.map { $0 * 100 }
            resetsAt = window.resetsAt
            durationMinutes = window.durationMinutes
        }
    }

    struct BestModel: Encodable {
        let category: String
        let model: String
        let providerModelID: String
        let intelligence: Double?
        let coding: Double?
        let agentic: Double?
        let availability: Double?
    }

    var generatedAt: Date
    var openrouter: ProviderSection
    var claude: ProviderSection
    var codexPersonal: ProviderSection
    var codexSecondary: ProviderSection
    var bestFreeModels: [BestModel]
    var notes: [String]
}
