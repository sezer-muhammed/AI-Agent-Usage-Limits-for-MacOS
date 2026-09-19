import Foundation

/// Replaces a file in one step so a reader — notably the widget — can never
/// observe a half-written JSON payload.
public struct AtomicFileWriter: Sendable {
    public init() {}

    public func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: [.atomic])

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            // replaceItemAt fails when the destination does not exist yet.
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }
}
