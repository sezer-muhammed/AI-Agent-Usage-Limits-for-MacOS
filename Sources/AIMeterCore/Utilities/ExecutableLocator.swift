import Foundation

/// Finds `claude` / `codex` without assuming the app inherited an interactive
/// shell PATH — a GUI-launched macOS app does not.
public struct ExecutableLocator: Sendable {
    public static let defaultSearchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        NSString(string: "~/.local/bin").expandingTildeInPath,
        NSString(string: "~/.bun/bin").expandingTildeInPath,
        NSString(string: "~/.npm-global/bin").expandingTildeInPath,
    ]

    private let searchPaths: [String]

    public init(searchPaths: [String] = ExecutableLocator.defaultSearchPaths) {
        self.searchPaths = searchPaths
    }

    /// Returns the first executable match, preferring a user-configured override.
    public func locate(_ name: String, userConfiguredPath: String? = nil) -> URL? {
        if let userConfiguredPath {
            let url = URL(fileURLWithPath: NSString(string: userConfiguredPath).expandingTildeInPath)
            if isExecutable(url) { return url }
        }

        for directory in searchPaths {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if isExecutable(url) { return url }
        }

        // Last resort: whatever PATH we did inherit.
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                let url = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
                if isExecutable(url) { return url }
            }
        }

        return nil
    }

    private func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }
}
