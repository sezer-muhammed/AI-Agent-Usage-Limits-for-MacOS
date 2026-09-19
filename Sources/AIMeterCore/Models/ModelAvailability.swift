import Foundation

/// Endpoint reliability, tracked separately from intelligence so a strong but
/// flaky model shows both facts instead of hiding one.
public struct ModelAvailability: Codable, Sendable, Hashable {
    public let percentage: Double?
    public let capturedAt: Date
    public let sampleWindowDescription: String?

    public init(percentage: Double?, capturedAt: Date, sampleWindowDescription: String? = nil) {
        self.percentage = percentage
        self.capturedAt = capturedAt
        self.sampleWindowDescription = sampleWindowDescription
    }
}
