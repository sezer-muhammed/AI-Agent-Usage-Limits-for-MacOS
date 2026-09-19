import AIMeterCore
import Foundation

/// Talks to the official OpenRouter REST API. The API key is read from the
/// Keychain at call time and never held beyond the request.
public struct OpenRouterClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://openrouter.ai/api/v1")!

    private let baseURL: URL
    private let http: HTTPClient
    private let apiKeyProvider: @Sendable () async throws -> String?

    public init(
        baseURL: URL = OpenRouterClient.defaultBaseURL,
        http: HTTPClient = HTTPClient(),
        apiKeyProvider: @escaping @Sendable () async throws -> String?
    ) {
        self.baseURL = baseURL
        self.http = http
        self.apiKeyProvider = apiKeyProvider
    }

    /// Convenience wiring for the app: key comes from the Keychain.
    public init(keychain: KeychainStore, baseURL: URL = OpenRouterClient.defaultBaseURL) {
        self.init(baseURL: baseURL) {
            try await keychain.secret(for: .openRouterAPIKey)
        }
    }

    func keyInfo() async throws -> OpenRouterDTO.KeyInfo {
        try await authorizedGet(
            OpenRouterDTO.Envelope<OpenRouterDTO.KeyInfo>.self,
            path: "key"
        ).data
    }

    func credits() async throws -> OpenRouterDTO.Credits {
        try await authorizedGet(
            OpenRouterDTO.Envelope<OpenRouterDTO.Credits>.self,
            path: "credits"
        ).data
    }

    /// The model catalog is public, so it works before a key is configured.
    func models() async throws -> [OpenRouterDTO.Model] {
        let url = baseURL.appendingPathComponent("models")
        do {
            return try await http.get(
                OpenRouterDTO.ModelList.self,
                url: url,
                headers: try await headers(requiresKey: false),
                decoder: JSONDecoder()
            ).data
        } catch let error as APIError {
            throw error.asProviderError
        }
    }

    /// Cheap credential check for Settings' "Test Connection".
    public func testConnection() async throws -> Bool {
        _ = try await keyInfo()
        return true
    }

    private func authorizedGet<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String
    ) async throws -> T {
        do {
            return try await http.get(
                type,
                url: baseURL.appendingPathComponent(path),
                headers: try await headers(requiresKey: true),
                decoder: JSONDecoder()
            )
        } catch let error as APIError {
            throw error.asProviderError
        }
    }

    private func headers(requiresKey: Bool) async throws -> [String: String] {
        var headers = [
            "Accept": "application/json",
            // OpenRouter uses these for attribution; they carry no user data.
            "HTTP-Referer": "https://github.com/sezer-muhammed/AI-Agent-Usage-Limits-for-MacOS",
            "X-Title": "AI Meter",
        ]

        let key = try await apiKeyProvider()
        if let key, !key.isEmpty {
            headers["Authorization"] = "Bearer \(key)"
        } else if requiresKey {
            throw ProviderError.configurationMissing("OpenRouter API key")
        }

        return headers
    }
}
