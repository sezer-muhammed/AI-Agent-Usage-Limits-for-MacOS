import AIMeterCore
import Foundation

/// Owns one short-lived `codex app-server` process and the JSON-RPC conversation
/// with it over stdio.
///
/// The process is started for a refresh and terminated as soon as the reads are
/// done — battery efficiency outweighs keeping two Codex servers resident. The
/// process is launched with an explicit argument list and environment, never a
/// shell string, so a configured path cannot become shell injection.
public actor CodexProcessController {
    public struct Configuration: Sendable {
        /// Isolated profile directory. Each account logs in independently here;
        /// auth files are never copied between profiles.
        public var codexHome: URL
        public var executableURL: URL?
        public var requestTimeout: TimeInterval

        public init(codexHome: URL, executableURL: URL? = nil, requestTimeout: TimeInterval = 30) {
            self.codexHome = codexHome
            self.executableURL = executableURL
            self.requestTimeout = requestTimeout
        }
    }

    private let configuration: Configuration
    private var process: Process?
    private var stdin: FileHandle?
    private var reader: LineReader?
    private var nextRequestID = 1

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// Starts the server and completes the `initialize` handshake.
    public func start() async throws {
        guard process == nil else { return }

        guard
            let executable = configuration.executableURL
                ?? ExecutableLocator().locate("codex")
        else {
            throw ProviderError.executableNotFound("codex")
        }

        try FileManager.default.createDirectory(
            at: configuration.codexHome,
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server"]

        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = configuration.codexHome.path
        process.environment = environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ProviderError.processFailed("could not launch codex app-server")
        }

        self.process = process
        self.stdin = inputPipe.fileHandleForWriting
        self.reader = LineReader(handle: outputPipe.fileHandleForReading)

        _ = try await request(
            CodexDTO.InitializeResponse.self,
            method: "initialize",
            params: CodexDTO.InitializeParams(
                clientInfo: CodexDTO.ClientInfo(name: "AI Meter", version: "1.0")
            )
        )
        try notify(method: "initialized")
    }

    /// Terminates the server. Always called once a refresh finishes.
    public func stop() {
        stdin.map { try? $0.close() }
        process?.terminate()
        process = nil
        stdin = nil
        reader = nil
    }

    public func isRunning() -> Bool {
        process?.isRunning == true
    }

    /// Sends a request and waits for the matching response, skipping the
    /// notifications the server interleaves.
    public func request<Response: Decodable & Sendable, Params: Encodable & Sendable>(
        _ type: Response.Type,
        method: String,
        params: Params? = Optional<EmptyParams>.none
    ) async throws -> Response {
        guard let stdin, let reader else { throw ProviderError.processFailed("not started") }

        let id = nextRequestID
        nextRequestID += 1

        // `params` is not optional on the wire: the server rejects a request
        // without it ("Invalid request: missing field `params`"), so methods
        // that take no arguments still send an empty object.
        var envelope: [String: Any] = ["id": id, "method": method, "params": [String: Any]()]
        if let params {
            let data = try JSONEncoder().encode(params)
            envelope["params"] = try JSONSerialization.jsonObject(with: data)
        }

        var line = try JSONSerialization.data(withJSONObject: envelope)
        line.append(0x0A)
        stdin.write(line)

        let deadline = Date().addingTimeInterval(configuration.requestTimeout)

        while Date() < deadline {
            guard let payload = try reader.nextLine(deadline: deadline) else {
                throw ProviderError.processFailed("codex app-server closed the connection")
            }

            guard
                let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                let responseID = object["id"] as? Int,
                responseID == id
            else {
                // A notification or another request's response: not ours.
                continue
            }

            if let error = object["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "unknown error"
                throw Self.providerError(forMessage: message)
            }

            guard let result = object["result"] else {
                throw ProviderError.malformedResponse("\(method): no result")
            }

            let resultData = try JSONSerialization.data(withJSONObject: result)
            do {
                return try JSONDecoder().decode(Response.self, from: resultData)
            } catch {
                throw ProviderError.malformedResponse("\(method): \(Response.self)")
            }
        }

        throw ProviderError.timeout
    }

    public func notify(method: String) throws {
        guard let stdin else { throw ProviderError.processFailed("not started") }
        var line = try JSONSerialization.data(withJSONObject: ["method": method])
        line.append(0x0A)
        stdin.write(line)
    }

    public struct EmptyParams: Encodable, Sendable {}

    /// Maps a server error message onto a typed error, so Settings can say
    /// something actionable instead of echoing raw text.
    private static func providerError(forMessage message: String) -> ProviderError {
        let lowered = message.lowercased()
        if lowered.contains("not logged in") || lowered.contains("auth") {
            return .unauthorized
        }
        if lowered.contains("method not found") || lowered.contains("unknown method") {
            return .unsupportedByInstalledVersion(message)
        }
        return .processFailed(message)
    }
}

/// Reads newline-delimited JSON from the server's stdout.
///
/// `FileHandle.availableData` blocks, so reads happen on a detached thread and
/// the actor waits on the result with a deadline.
private final class LineReader: @unchecked Sendable {
    private let handle: FileHandle
    private var buffer = Data()
    private var isAtEnd = false

    init(handle: FileHandle) {
        self.handle = handle
    }

    func nextLine(deadline: Date) throws -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if line.isEmpty { continue }
                return Data(line)
            }

            if isAtEnd { return nil }
            guard Date() < deadline else { throw ProviderError.timeout }

            let chunk = handle.availableData
            if chunk.isEmpty {
                isAtEnd = true
                continue
            }
            buffer.append(chunk)
        }
    }
}
