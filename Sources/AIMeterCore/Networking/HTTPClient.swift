import Foundation

/// A thin `URLSession` wrapper: async/await, typed errors, and a conservative
/// retry policy. No third-party networking dependency.
public actor HTTPClient {
    public struct Configuration: Sendable {
        public var timeout: TimeInterval
        public var maxRetries: Int
        public var baseBackoff: TimeInterval

        public init(timeout: TimeInterval = 20, maxRetries: Int = 2, baseBackoff: TimeInterval = 0.5) {
            self.timeout = timeout
            self.maxRetries = maxRetries
            self.baseBackoff = baseBackoff
        }
    }

    private let session: URLSession
    private let configuration: Configuration

    public init(configuration: Configuration = Configuration(), session: URLSession? = nil) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            let sessionConfiguration = URLSessionConfiguration.ephemeral
            sessionConfiguration.timeoutIntervalForRequest = configuration.timeout
            sessionConfiguration.waitsForConnectivity = false
            self.session = URLSession(configuration: sessionConfiguration)
        }
    }

    public func get<T: Decodable & Sendable>(
        _ type: T.Type,
        url: URL,
        headers: [String: String] = [:],
        decoder: JSONDecoder = DateFormatting.makeDecoder()
    ) async throws -> T {
        let data = try await data(url: url, headers: headers)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Deliberately does not include the payload: it may carry account data.
            throw APIError.decoding("\(T.self): \(error)")
        }
    }

    public func data(url: URL, headers: [String: String] = [:]) async throws -> Data {
        var attempt = 0
        while true {
            do {
                return try await performOnce(url: url, headers: headers)
            } catch let error as APIError where error.isRetryable && attempt < configuration.maxRetries {
                attempt += 1
                let delay = configuration.baseBackoff * pow(2, Double(attempt - 1))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func performOnce(url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = configuration.timeout
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("non-HTTP response")
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw APIError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retryAfter)
        case 400..<500:
            throw APIError.client(status: http.statusCode)
        default:
            throw APIError.server(status: http.statusCode)
        }
    }
}
