import AIMeterCore
import Foundation

/// Installs, repairs and removes the status-line integration in
/// `~/.claude/settings.json`.
///
/// The user's existing status line is never silently overwritten: the installer
/// reports what it found, chains to it when one exists, writes a timestamped
/// backup before touching the file, and can put everything back.
public struct ClaudeIntegrationInstaller: Sendable {
    public struct State: Sendable, Equatable {
        public enum ExistingStatusLine: Sendable, Equatable {
            case none
            /// Someone else's status line — chain to it rather than replace it.
            case other(command: String)
            /// Already ours.
            case aiMeter(command: String)
        }

        public let claudeInstalled: Bool
        public let settingsExists: Bool
        public let existing: ExistingStatusLine
        public let bridgeInstalled: Bool
    }

    /// Exactly what an install would change, shown to the user before it runs.
    public struct Plan: Sendable, Equatable {
        public let settingsURL: URL
        public let backupURL: URL?
        public let previousCommand: String?
        public let newCommand: String
        public let chainsToPrevious: Bool
    }

    public enum InstallerError: Error, Sendable {
        case settingsUnreadable
        case settingsNotJSONObject
        case nothingToRemove
    }

    private let settingsURL: URL
    private let bridgeExecutableURL: URL
    private let telemetryURL: URL

    // FileManager.default is documented as thread-safe for these operations, but
    // it is not Sendable; the struct reaches for it rather than storing it.
    private var fileManager: FileManager { .default }

    public init(
        settingsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json"),
        bridgeExecutableURL: URL,
        telemetryURL: URL = ClaudeTelemetry.defaultURL()
    ) {
        self.settingsURL = settingsURL
        self.bridgeExecutableURL = bridgeExecutableURL
        self.telemetryURL = telemetryURL
    }

    /// The command written into settings. `--forward` makes the bridge tee stdin
    /// to the user's previous status line and pass its output through, so their
    /// status line keeps rendering exactly as before.
    public func command(chainingTo previous: String?) -> String {
        var command = "\(shellQuoted(bridgeExecutableURL.path)) --out \(shellQuoted(telemetryURL.path))"
        if let previous, !previous.isEmpty {
            command += " --forward \(shellQuoted(previous))"
        }
        return command
    }

    public func inspect(claudeExecutable: URL? = ExecutableLocator().locate("claude")) throws -> State {
        let settings = try? loadSettings()
        let statusLine = (settings?["statusLine"] as? [String: Any])
        let existingCommand = statusLine?["command"] as? String

        let existing: State.ExistingStatusLine =
            switch existingCommand {
            case .none: .none
            case .some(let command) where command.contains(bridgeExecutableName): .aiMeter(command: command)
            case .some(let command): .other(command: command)
            }

        return State(
            claudeInstalled: claudeExecutable != nil,
            settingsExists: fileManager.fileExists(atPath: settingsURL.path),
            existing: existing,
            bridgeInstalled: fileManager.isExecutableFile(atPath: bridgeExecutableURL.path)
        )
    }

    /// Describes the change without performing it.
    public func plan(replaceExisting: Bool) throws -> Plan {
        let state = try inspect()

        let previous: String? =
            switch state.existing {
            case .other(let command): command
            // Re-installing over ourselves must not chain to our own command.
            case .aiMeter, .none: nil
            }

        let chains = previous != nil && !replaceExisting

        return Plan(
            settingsURL: settingsURL,
            backupURL: state.settingsExists ? backupURL() : nil,
            previousCommand: previous,
            newCommand: command(chainingTo: chains ? previous : nil),
            chainsToPrevious: chains
        )
    }

    @discardableResult
    public func install(replaceExisting: Bool = false) throws -> Plan {
        let plan = try plan(replaceExisting: replaceExisting)

        var settings = (try? loadSettings()) ?? [:]

        if let backupURL = plan.backupURL {
            try fileManager.copyItem(at: settingsURL, to: backupURL)
        }

        // Remember what was there so removal can restore it exactly.
        var aiMeter: [String: Any] = ["managed": true]
        if let previous = plan.previousCommand {
            aiMeter["previousStatusLineCommand"] = previous
        }
        settings["aiMeter"] = aiMeter

        var statusLine = (settings["statusLine"] as? [String: Any]) ?? [:]
        statusLine["type"] = "command"
        statusLine["command"] = plan.newCommand
        settings["statusLine"] = statusLine

        try writeSettings(settings)
        return plan
    }

    /// Reverses an install, restoring the user's previous status line if there was one.
    public func remove() throws {
        var settings = try loadSettings()

        guard let aiMeter = settings["aiMeter"] as? [String: Any] else {
            throw InstallerError.nothingToRemove
        }

        if let previous = aiMeter["previousStatusLineCommand"] as? String {
            settings["statusLine"] = ["type": "command", "command": previous]
        } else {
            settings["statusLine"] = nil
        }
        settings["aiMeter"] = nil

        try writeSettings(settings)
    }

    private var bridgeExecutableName: String { bridgeExecutableURL.lastPathComponent }

    private func backupURL() -> URL {
        let stamp = Int(Date().timeIntervalSince1970)
        return settingsURL.deletingLastPathComponent()
            .appendingPathComponent("settings.json.aimeter-backup-\(stamp)")
    }

    private func loadSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL) else {
            throw InstallerError.settingsUnreadable
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallerError.settingsNotJSONObject
        }
        return object
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try AtomicFileWriter().write(data, to: settingsURL)
    }

    /// Claude Code runs the status-line command through a shell, so paths are
    /// single-quoted rather than interpolated raw.
    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
