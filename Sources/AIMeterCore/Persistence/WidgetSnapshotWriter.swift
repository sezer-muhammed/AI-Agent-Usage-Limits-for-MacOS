import Foundation

/// Publishes the widget payload into the App Group container.
///
/// The widget reads this file and nothing else: no network, no database, no
/// credentials.
public struct WidgetSnapshotWriter: WidgetSnapshotWriting {
    public static let fileName = "widget-snapshot.json"

    private let containerURL: URL
    private let writer = AtomicFileWriter()
    private let reloadWidgets: @Sendable () -> Void

    public init(containerURL: URL, reloadWidgets: @escaping @Sendable () -> Void = {}) {
        self.containerURL = containerURL
        self.reloadWidgets = reloadWidgets
    }

    /// Resolves the shared container, falling back to Application Support when the
    /// App Group is not configured yet (development, or before entitlements exist).
    public init?(appGroupIdentifier: String, reloadWidgets: @escaping @Sendable () -> Void = {}) {
        let fileManager = FileManager.default
        let fallback = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("AIMeter", isDirectory: true)

        guard
            let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
                ?? fallback
        else { return nil }

        self.init(containerURL: url, reloadWidgets: reloadWidgets)
    }

    public var snapshotURL: URL { containerURL.appendingPathComponent(Self.fileName) }

    public func write(_ snapshot: WidgetSnapshot) async throws {
        let data = try DateFormatting.makeEncoder().encode(snapshot)
        try writer.write(data, to: snapshotURL)
        reloadWidgets()
        AIMeterLog.widget.debug("Wrote widget snapshot (\(data.count, privacy: .public) bytes)")
    }

    public func read() throws -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try DateFormatting.makeDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
