import AIMeterCore
import Foundation

/// One Codex account. Two accounts mean two adapters with two isolated
/// `CODEX_HOME` directories — never one profile with copied credentials, which
/// refresh-token rotation would break.
public struct CodexAccountAdapter: UsageProvider, Sendable {
    public let providerID: Provider.ID = Provider.codex.id
    public let accountID: String
    public let displayName: String

    private let client: CodexAppServerClient
    private let codexHome: URL
    private let now: @Sendable () -> Date

    public init(
        accountID: String,
        displayName: String,
        codexHome: URL,
        executableURL: URL? = nil,
        requestTimeout: TimeInterval = 30,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.accountID = accountID
        self.displayName = displayName
        self.codexHome = codexHome
        self.now = now
        self.client = CodexAppServerClient(
            accountID: accountID,
            configuration: CodexProcessController.Configuration(
                codexHome: codexHome,
                executableURL: executableURL,
                requestTimeout: requestTimeout
            )
        )
    }

    public var profilePath: String { codexHome.path }

    public var account: ProviderAccount {
        ProviderAccount(
            id: accountID,
            provider: .codex,
            displayName: displayName,
            profilePath: codexHome.path
        )
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let data = try await client.read()

        return UsageSnapshot(
            provider: .codex,
            accountID: accountID,
            capturedAt: now(),
            windows: data.rateLimits,
            creditsRemainingUSD: data.creditsRemainingUSD,
            activeModelID: nil,
            planLabel: data.planLabel
        )
    }

    /// Models this specific account can reach — the account view, not a catalog.
    public func fetchModels() async throws -> [AIModel] {
        try await client.read().models
    }

    /// Everything in one server session, for callers that want both without
    /// paying to start the process twice.
    public func read() async throws -> CodexAppServerClient.AccountData {
        try await client.read()
    }
}
