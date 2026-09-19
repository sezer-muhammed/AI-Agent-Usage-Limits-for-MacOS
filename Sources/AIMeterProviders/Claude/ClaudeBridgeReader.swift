import AIMeterCore
import Foundation

/// Reads the sanitized telemetry file the bridge writes.
public struct ClaudeBridgeReader: Sendable {
    private let url: URL

    public init(url: URL = ClaudeTelemetry.defaultURL()) {
        self.url = url
    }

    public var telemetryURL: URL { url }

    public var isInstalled: Bool { FileManager.default.fileExists(atPath: url.path) }

    public func read() throws -> ClaudeTelemetry {
        guard let data = try? Data(contentsOf: url) else {
            throw ProviderError.configurationMissing("Claude bridge telemetry")
        }
        do {
            return try DateFormatting.makeDecoder().decode(ClaudeTelemetry.self, from: data)
        } catch {
            throw ProviderError.malformedResponse("Claude telemetry file")
        }
    }
}
