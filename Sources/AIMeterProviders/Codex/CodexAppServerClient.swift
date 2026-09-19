import AIMeterCore
import Foundation

/// The four reads AI Meter needs from a Codex account, in one short-lived
/// server session: start, read, terminate.
public struct CodexAppServerClient: Sendable {
    public struct AccountData: Sendable {
        public let account: CodexAccountInfo?
        public let rateLimits: [RateLimitWindow]
        public let creditsRemainingUSD: Decimal?
        public let planLabel: String?
        public let models: [AIModel]
        /// Reads the installed Codex version did not support, surfaced in the UI
        /// as "unavailable in this version" rather than silently dropped.
        public let unsupported: [String]
    }

    public struct CodexAccountInfo: Sendable {
        public let type: String?
        public let email: String?
        public let planType: String?
    }

    private let configuration: CodexProcessController.Configuration
    private let accountID: String
    private let canonicalizer: ModelCanonicalizer

    public init(
        accountID: String,
        configuration: CodexProcessController.Configuration,
        canonicalizer: ModelCanonicalizer = ModelCanonicalizer()
    ) {
        self.accountID = accountID
        self.configuration = configuration
        self.canonicalizer = canonicalizer
    }

    public func read() async throws -> AccountData {
        let controller = CodexProcessController(configuration: configuration)
        // The server is torn down even when a read throws: no stray processes.
        defer { Task { await controller.stop() } }

        try await controller.start()

        var unsupported: [String] = []

        let account = try await optional(&unsupported, "account/read") {
            try await controller.request(
                CodexDTO.GetAccountResponse.self,
                method: "account/read",
                params: Optional<CodexProcessController.EmptyParams>.none
            )
        }

        let limits = try await optional(&unsupported, "account/rateLimits/read") {
            try await controller.request(
                CodexDTO.GetAccountRateLimitsResponse.self,
                method: "account/rateLimits/read",
                params: Optional<CodexProcessController.EmptyParams>.none
            )
        }

        // Token usage is informational; its absence must not fail the refresh.
        _ = try await optional(&unsupported, "account/usage/read") {
            try await controller.request(
                CodexDTO.GetAccountTokenUsageResponse.self,
                method: "account/usage/read",
                params: Optional<CodexProcessController.EmptyParams>.none
            )
        }

        let models = try await optional(&unsupported, "model/list") {
            try await controller.request(
                CodexDTO.ModelListResponse.self,
                method: "model/list",
                params: Optional<CodexProcessController.EmptyParams>.none
            )
        }

        let snapshot = limits?.rateLimits
        let credits = snapshot?.credits?.balance.flatMap { Decimal(string: $0) }

        return AccountData(
            account: account?.account.map {
                CodexAccountInfo(type: $0.type, email: $0.email, planType: $0.planType)
            },
            rateLimits: windows(from: limits),
            creditsRemainingUSD: credits,
            planLabel: account?.account?.planType ?? snapshot?.planType,
            models: (models?.data ?? []).compactMap(normalize),
            unsupported: unsupported
        )
    }

    /// Runs a read, recording methods the installed version rejects instead of
    /// aborting the whole refresh.
    private func optional<T: Sendable>(
        _ unsupported: inout [String],
        _ method: String,
        _ body: () async throws -> T
    ) async throws -> T? {
        do {
            return try await body()
        } catch ProviderError.unsupportedByInstalledVersion {
            unsupported.append(method)
            return nil
        } catch ProviderError.malformedResponse {
            unsupported.append(method)
            return nil
        }
    }

    private func windows(from response: CodexDTO.GetAccountRateLimitsResponse?) -> [RateLimitWindow] {
        guard let response else { return [] }

        // Prefer the multi-bucket view; fall back to the single-bucket mirror.
        let snapshots: [(String, CodexDTO.RateLimitSnapshot)] =
            if let byLimit = response.rateLimitsByLimitId, !byLimit.isEmpty {
                byLimit.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
            } else if let single = response.rateLimits {
                [(single.limitId ?? "default", single)]
            } else {
                []
            }

        return snapshots.flatMap { limitID, snapshot in
            [
                window(snapshot.primary, limitID: limitID, position: "primary", name: snapshot.limitName),
                window(snapshot.secondary, limitID: limitID, position: "secondary", name: snapshot.limitName),
            ].compactMap { $0 }
        }
    }

    private func window(
        _ dto: CodexDTO.RateLimitWindowDTO?,
        limitID: String,
        position: String,
        name: String?
    ) -> RateLimitWindow? {
        guard let dto else { return nil }

        // Codex labels windows by duration, not by name.
        let kind = RateLimitWindow.kind(forDurationMinutes: dto.windowDurationMins)
        let label = Self.label(forKind: kind, limitName: name)

        return RateLimitWindow(
            id: "\(accountID).\(limitID).\(position)",
            kind: kind,
            usedFraction: dto.usedPercent.map { min(max($0 / 100, 0), 1) },
            resetsAt: dto.resetsAt.map(Date.init(timeIntervalSince1970:)),
            durationMinutes: dto.windowDurationMins,
            label: label
        )
    }

    private static func label(forKind kind: RateLimitWindow.Kind, limitName: String?) -> String {
        let base =
            switch kind {
            case .session: "Session"
            case .fiveHour: "5-hour window"
            case .daily: "Daily"
            case .weekly: "Weekly"
            case .monthly: "Monthly"
            case .custom: "Usage"
            }
        guard let limitName, !limitName.isEmpty else { return base }
        return "\(limitName) · \(base)"
    }

    private func normalize(_ dto: CodexDTO.Model) -> AIModel? {
        guard let id = dto.id ?? dto.model else { return nil }
        return AIModel(
            id: id,
            canonicalID: canonicalizer.canonicalID(forProviderModelID: dto.model ?? id),
            displayName: dto.displayName ?? id,
            provider: "openai",
            sourceProviderID: Provider.codex.id,
            contextLength: nil,
            inputPricePerMillion: nil,
            outputPricePerMillion: nil,
            // Codex models come with a subscription; they are not free variants.
            isFreeVariant: false,
            supportedModalities: dto.inputModalities ?? []
        )
    }
}
