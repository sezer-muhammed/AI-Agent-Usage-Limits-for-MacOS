import Foundation

public enum APIError: Error, Sendable, Hashable {
    case invalidURL
    case transport(String)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int)
    case client(status: Int)
    case decoding(String)

    /// Only transient conditions are worth a retry; an auth failure never is.
    public var isRetryable: Bool {
        switch self {
        case .transport, .server: true
        case .rateLimited: true
        case .invalidURL, .unauthorized, .client, .decoding: false
        }
    }

    public var asProviderError: ProviderError {
        switch self {
        case .unauthorized: .unauthorized
        case .decoding(let detail): .malformedResponse(detail)
        case .transport, .server, .rateLimited, .client: .unavailable
        case .invalidURL: .configurationMissing("endpoint URL")
        }
    }
}
