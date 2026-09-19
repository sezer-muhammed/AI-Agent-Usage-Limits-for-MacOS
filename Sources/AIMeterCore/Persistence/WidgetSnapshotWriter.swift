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

    /// Resolves where the app and the widget exchange the snapshot.
    ///
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` returns a path even
    /// when the process has no App Group entitlement — but the directory does not
    /// exist and creating it is refused ("Operation not permitted"), so trusting
    /// that path leaves the widget permanently blank. The container is used only
    /// when the system has actually provisioned it; otherwise both processes fall
    /// back to Application Support, which an unsandboxed build can share.
    public init?(appGroupIdentifier: String, reloadWidgets: @escaping @Sendable () -> Void = {}) {
        let fileManager = FileManager.default

        if let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ), fileManager.fileExists(atPath: container.path) {
            self.init(containerURL: container, reloadWidgets: reloadWidgets)
            return
        }

        guard
            let fallback = try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("AIMeter", isDirectory: true)
        else { return nil }

        self.init(containerURL: fallback, reloadWidgets: reloadWidgets)
    }

    public var snapshotURL: URL { containerURL.appendingPathComponent(Self.fileName) }

    /// Where a sandboxed widget extension's own Application Support lives.
    ///
    /// A WidgetKit extension must be sandboxed or macOS will not register it,
    /// and a sandboxed extension can only read its own container. Sharing
    /// through an App Group is the proper answer, but that needs a provisioned
    /// team. Until then the unsandboxed app — which can write anywhere the user
    /// can — publishes directly into the extension's container, which the
    /// extension then reads as its ordinary Application Support directory.
    public static func sandboxedExtensionContainerURL(
        bundleIdentifier: String,
        fileManager: FileManager = .default
    ) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
            .appendingPathComponent("AIMeter", isDirectory: true)
    }

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
