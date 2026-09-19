import AIMeterCore
import AIMeterProviders
import Foundation
import WidgetKit

/// Wires the data layer together once, at launch.
///
/// The UI never reaches a provider directly — it talks to `AppState`, which
/// talks to the refresh coordinator, which owns the adapters.
@MainActor
final class AppEnvironment {
    static let appGroupIdentifier = "group.com.sezer-muhammed.aimeter"
    static let widgetBundleIdentifier = "com.sezer-muhammed.aimeter.widget"

    let keychain = KeychainStore()
    /// One Keychain read per launch instead of one per request — see
    /// `CachedCredential` for why that matters on an ad-hoc signed build.
    let openRouterKey: CachedCredential
    let coordinator: RefreshCoordinator

    /// Where the widget payload is published; surfaced so Settings can show it.
    private(set) var widgetSnapshotURL: URL?
    private(set) var database: Database?
    private(set) var usageRepository: UsageSnapshotRepository?
    private(set) var modelRepository: ModelSnapshotRepository?

    let openRouterClient: OpenRouterClient
    let codexAccounts: [CodexAccountAdapter]
    let claudeReader = ClaudeBridgeReader()
    /// Scores come from a feed on disk; nothing measures models in-app.
    let benchmarks = FileBenchmarkProvider()

    init() {
        let keychain = self.keychain
        let openRouterKey = CachedCredential(keychain: keychain, key: .openRouterAPIKey)
        self.openRouterKey = openRouterKey
        openRouterClient = OpenRouterClient { try await openRouterKey.value() }

        codexAccounts = [
            CodexAccountAdapter(
                accountID: "codex-personal",
                displayName: "Codex · Personal",
                codexHome: Self.codexHome("personal")
            ),
            CodexAccountAdapter(
                accountID: "codex-secondary",
                displayName: "Codex · Secondary",
                codexHome: Self.codexHome("secondary")
            ),
        ]

        let reload: @Sendable () -> Void = { WidgetCenter.shared.reloadAllTimelines() }

        // Prefer a real App Group when one is provisioned; otherwise publish into
        // the sandboxed widget's own container, which is the only place that
        // extension can read without a signing team.
        let groupContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        )
        let usesAppGroup =
            groupContainer.map { FileManager.default.fileExists(atPath: $0.path) } ?? false

        let writer: WidgetSnapshotWriter =
            if usesAppGroup, let groupContainer {
                WidgetSnapshotWriter(containerURL: groupContainer, reloadWidgets: reload)
            } else {
                WidgetSnapshotWriter(
                    containerURL: WidgetSnapshotWriter.sandboxedExtensionContainerURL(
                        bundleIdentifier: Self.widgetBundleIdentifier
                    ),
                    reloadWidgets: reload
                )
            }

        widgetSnapshotURL = writer.snapshotURL
        coordinator = RefreshCoordinator(widgetWriter: writer)
    }

    /// Opens the database and registers every configured account.
    func bootstrap() async {
        do {
            let database = try Database(url: Self.databaseURL())
            try await Migrations.migrate(database)

            let usageRepository = UsageSnapshotRepository(database: database) { id in
                switch id {
                case Provider.claude.id: .claude
                case Provider.codex.id: .codex
                default: .openRouter
                }
            }

            self.database = database
            self.usageRepository = usageRepository
            self.modelRepository = ModelSnapshotRepository(database: database)

            // Without this the refresh keeps no history at all.
            await coordinator.attach(usageRepository: usageRepository)
        } catch {
            AIMeterLog.storage.error("Could not open the database: \(String(describing: error))")
        }

        await registerProviders()
        // Cached data renders before any network call happens.
        await coordinator.primeFromCache()
    }

    private func registerProviders() async {
        let client = openRouterClient
        await coordinator.register(
            RefreshCoordinator.Registration(
                account: ProviderAccount(
                    id: "openrouter",
                    provider: .openRouter,
                    displayName: "OpenRouter"
                ),
                policy: .openRouter
            ) {
                try await OpenRouterUsageAdapter(client: client).fetchUsage()
            }
        )

        let reader = claudeReader
        await coordinator.register(
            RefreshCoordinator.Registration(
                account: ProviderAccount(id: "claude", provider: .claude, displayName: "Claude"),
                policy: .claude
            ) {
                try await ClaudeStatusAdapter(reader: reader).fetchUsage()
            }
        )

        for adapter in codexAccounts {
            await coordinator.register(
                RefreshCoordinator.Registration(account: adapter.account, policy: .codex) {
                    try await adapter.fetchUsage()
                }
            )
        }
    }

    static func codexHome(_ profile: String) -> URL {
        URL(
            fileURLWithPath: NSString(string: "~/.codex-aimeter-\(profile)").expandingTildeInPath
        )
    }

    static func databaseURL() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("AIMeter", isDirectory: true)
            .appendingPathComponent("history.sqlite")
    }
}
