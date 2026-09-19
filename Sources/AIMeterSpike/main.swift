import AIMeterCore
import AIMeterProviders
import Foundation

// aimeter-spike — the integration feasibility harness from section 86 of the
// specification.
//
// It proves the four provider flows against real installations and prints one
// normalized JSON document. This runs before any UI work: if a provider cannot
// supply a field, that has to be visible here rather than discovered later.
//
// Usage:
//   swift run aimeter-spike
//   swift run aimeter-spike --set-openrouter-key      (reads the key from stdin)
//   swift run aimeter-spike --forget-openrouter-key
//   swift run aimeter-spike --install-claude-bridge
//   swift run aimeter-spike --remove-claude-bridge
//   swift run aimeter-spike --codex-home-a ~/.codex-aimeter-personal
//
// The output can contain real account data (plan, spend, reset times), so it is
// printed to stdout and never written into the repository.

/// Reads a line from the terminal with echo turned off, so a pasted credential
/// does not stay visible in the scrollback. Falls back to a plain read when
/// stdin is not a terminal (a pipe, or CI).
func readSecretLine() -> String? {
    guard isatty(STDIN_FILENO) == 1 else { return readLine(strippingNewline: true) }

    var original = termios()
    guard tcgetattr(STDIN_FILENO, &original) == 0 else {
        return readLine(strippingNewline: true)
    }

    var silenced = original
    silenced.c_lflag &= ~tcflag_t(ECHO)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &silenced)
    defer {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        // The user's Return was swallowed along with the echo.
        FileHandle.standardError.write(Data("\n".utf8))
    }

    return readLine(strippingNewline: true)
}

enum Command {
    case runSpike
    case setOpenRouterKey
    case forgetOpenRouterKey
    case installClaudeBridge
    case removeClaudeBridge
}

struct Options {
    var command: Command = .runSpike
    var codexHomeA = URL(
        fileURLWithPath: NSString(string: "~/.codex-aimeter-personal").expandingTildeInPath
    )
    var codexHomeB = URL(
        fileURLWithPath: NSString(string: "~/.codex-aimeter-secondary").expandingTildeInPath
    )
    var claudeTelemetryURL = ClaudeTelemetry.defaultURL()
    var claudeSettingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")
    /// Replace an existing status line instead of chaining to it.
    var replaceExistingStatusLine = false

    init(_ raw: [String]) {
        var index = 0
        while index < raw.count {
            let next = index + 1 < raw.count ? raw[index + 1] : nil
            switch raw[index] {
            case "--codex-home-a":
                if let next { codexHomeA = URL(fileURLWithPath: NSString(string: next).expandingTildeInPath) }
                index += 2
            case "--codex-home-b":
                if let next { codexHomeB = URL(fileURLWithPath: NSString(string: next).expandingTildeInPath) }
                index += 2
            case "--claude-telemetry":
                if let next { claudeTelemetryURL = URL(fileURLWithPath: next) }
                index += 2
            case "--set-openrouter-key":
                command = .setOpenRouterKey
                index += 1
            case "--forget-openrouter-key":
                command = .forgetOpenRouterKey
                index += 1
            case "--install-claude-bridge":
                command = .installClaudeBridge
                index += 1
            case "--remove-claude-bridge":
                command = .removeClaudeBridge
                index += 1
            case "--replace-status-line":
                replaceExistingStatusLine = true
                index += 1
            case "--claude-settings":
                if let next { claudeSettingsURL = URL(fileURLWithPath: NSString(string: next).expandingTildeInPath) }
                index += 2
            default:
                index += 1
            }
        }
    }
}

let options = Options(Array(CommandLine.arguments.dropFirst()))
let keychain = KeychainStore()

// MARK: Credential commands
//
// The app will do this from Settings; until that UI exists these two commands
// put the key in the same place — the Keychain — so nothing has to change later.

switch options.command {
case .setOpenRouterKey:
    // Read from stdin, never from an argument: an argument would land in shell
    // history and in the process list.
    FileHandle.standardError.write(
        Data("Paste your OpenRouter API key, then press Return (input is hidden):\n".utf8)
    )
    let entered = readSecretLine()?.trimmingCharacters(in: .whitespacesAndNewlines)

    guard let entered, !entered.isEmpty else {
        FileHandle.standardError.write(Data("No key entered; nothing was stored.\n".utf8))
        exit(1)
    }

    do {
        try await keychain.setSecret(entered, for: .openRouterAPIKey)
    } catch {
        FileHandle.standardError.write(Data("Could not write to the Keychain: \(error)\n".utf8))
        exit(1)
    }

    // Prove the key works before declaring success.
    let client = OpenRouterClient(keychain: keychain)
    do {
        _ = try await client.testConnection()
        print("Stored in the Keychain and verified: \(KeychainStore.redacted(entered))")
    } catch {
        print(
            "Stored in the Keychain as \(KeychainStore.redacted(entered)), "
                + "but the connection test failed: "
                + ((error as? ProviderError)?.errorDescription ?? error.localizedDescription)
        )
        exit(1)
    }
    exit(0)

case .forgetOpenRouterKey:
    do {
        try await keychain.deleteSecret(for: .openRouterAPIKey)
        print("Removed the OpenRouter key from the Keychain.")
    } catch {
        FileHandle.standardError.write(Data("Could not remove the key: \(error)\n".utf8))
        exit(1)
    }
    exit(0)

case .installClaudeBridge:
    // The bridge must be the built binary, not this debug harness.
    let bridgeURL = URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent()
        .appendingPathComponent("aimeter-claude-bridge")

    guard FileManager.default.isExecutableFile(atPath: bridgeURL.path) else {
        FileHandle.standardError.write(
            Data("Build it first: swift build -c release\nExpected at \(bridgeURL.path)\n".utf8)
        )
        exit(1)
    }

    let installer = ClaudeIntegrationInstaller(
        settingsURL: options.claudeSettingsURL,
        bridgeExecutableURL: bridgeURL,
        telemetryURL: options.claudeTelemetryURL
    )

    do {
        let state = try installer.inspect()
        switch state.existing {
        case .none:
            print("No existing status line found.")
        case .aiMeter:
            print("AI Meter's status line is already installed; it will be refreshed.")
        case .other(let command):
            print("Existing status line found:\n  \(command)")
            print(
                options.replaceExistingStatusLine
                    ? "It will be REPLACED (--replace-status-line)."
                    : "It will be preserved: AI Meter chains to it and passes its output through."
            )
        }

        // Say exactly what changes, then make it reversible.
        let plan = try installer.install(replaceExisting: options.replaceExistingStatusLine)

        print("\nSettings: \(plan.settingsURL.path)")
        if let backup = plan.backupURL {
            print("Backup:   \(backup.path)")
        }
        print("Command:  \(plan.newCommand)")
        print("\nInstalled. Claude Code writes telemetry on its next status-line update.")
        print("Undo with: swift run aimeter-spike --remove-claude-bridge")
    } catch {
        FileHandle.standardError.write(Data("Install failed: \(error)\n".utf8))
        exit(1)
    }
    exit(0)

case .removeClaudeBridge:
    let installer = ClaudeIntegrationInstaller(
        settingsURL: options.claudeSettingsURL,
        bridgeExecutableURL: URL(fileURLWithPath: "/nonexistent"),
        telemetryURL: options.claudeTelemetryURL
    )

    do {
        try installer.remove()
        print("Removed. Any status line that was there before has been restored.")
    } catch {
        FileHandle.standardError.write(Data("Remove failed: \(error)\n".utf8))
        exit(1)
    }
    exit(0)

case .runSpike:
    break
}

var notes: [String] = []

// MARK: OpenRouter

// The Keychain is the real source. The environment variable stays supported as a
// convenience for one-off runs and for CI, and takes precedence when set.
func resolveOpenRouterKey(_ keychain: KeychainStore) async -> String? {
    if let fromEnvironment = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"],
        !fromEnvironment.isEmpty
    {
        return fromEnvironment
    }
    return try? await keychain.secret(for: .openRouterAPIKey)
}

let openRouterKey = await resolveOpenRouterKey(keychain)

let openRouterClient = OpenRouterClient { openRouterKey }
let modelsAdapter = OpenRouterModelsAdapter(client: openRouterClient)

var catalog: [AIModel] = []
var openRouterSection: SpikeReport.ProviderSection

do {
    catalog = try await modelsAdapter.fetchModels()
    let free = catalog.filter(\.isFreeVariant)

    if openRouterKey?.isEmpty == false {
        let usage = try await OpenRouterUsageAdapter(client: openRouterClient).fetchUsage()
        openRouterSection = SpikeReport.ProviderSection(
            status: "ok",
            detail: "\(catalog.count) models, \(free.count) free variants",
            planLabel: usage.planLabel,
            windows: usage.windows.map(SpikeReport.Window.init),
            spendTodayUSD: usage.spendTodayUSD.map { "\($0)" },
            creditsRemainingUSD: usage.creditsRemainingUSD.map { "\($0)" },
            modelCount: catalog.count,
            sampleModels: free.prefix(5).map(\.id),
            capturedAt: usage.capturedAt
        )
    } else {
        // The catalog is public, so the spike still proves that half of the flow.
        openRouterSection = SpikeReport.ProviderSection(
            status: "partial",
            detail: "no API key supplied; catalog read only",
            modelCount: catalog.count,
            sampleModels: free.prefix(5).map(\.id)
        )
        notes.append(
            "No OpenRouter key configured, so /key and /credits were not exercised. "
                + "Store one with: swift run aimeter-spike --set-openrouter-key"
        )
    }
} catch {
    openRouterSection = .failed(error)
}

// Benchmarks are not exposed by the OpenRouter catalog, so nothing is invented
// here: without a benchmark source the ranking engine correctly ranks nothing.
let ranked = ModelRankingEngine().bestFree(catalog)
if ranked.isEmpty && !catalog.isEmpty {
    notes.append(
        "No benchmark source is configured, so no free model can be ranked. "
            + "The catalog itself carries no intelligence/coding/agentic scores."
    )
}

// MARK: Claude

let claudeReader = ClaudeBridgeReader(url: options.claudeTelemetryURL)
let claudeAdapter = ClaudeStatusAdapter(reader: claudeReader)

let claudeSection: SpikeReport.ProviderSection
do {
    let usage = try await claudeAdapter.fetchUsage()
    claudeSection = SpikeReport.ProviderSection(
        status: usage.windows.isEmpty ? "partial" : "ok",
        detail: usage.windows.isEmpty
            ? "bridge installed but no rate_limits yet (subscription-only, appears after the first API response)"
            : nil,
        windows: usage.windows.map(SpikeReport.Window.init),
        capturedAt: usage.capturedAt,
        freshness: claudeAdapter.freshness()?.rawValue
    )
} catch {
    claudeSection = .failed(error)
    notes.append("Install the Claude bridge to populate \(options.claudeTelemetryURL.path).")
}

// MARK: Codex, both accounts independently

func readCodex(accountID: String, displayName: String, home: URL) async -> SpikeReport.ProviderSection
{
    let adapter = CodexAccountAdapter(accountID: accountID, displayName: displayName, codexHome: home)
    do {
        let data = try await adapter.read()
        return SpikeReport.ProviderSection(
            status: data.rateLimits.isEmpty ? "partial" : "ok",
            detail: data.requiresAuthentication
                ? "profile is not signed in; model/list still works"
                : nil,
            planLabel: data.planLabel,
            windows: data.rateLimits.map(SpikeReport.Window.init),
            creditsRemainingUSD: data.creditsRemainingUSD.map { "\($0)" },
            modelCount: data.models.count,
            sampleModels: data.models.prefix(5).map(\.id),
            capturedAt: Date(),
            unsupportedMethods: data.unsupported.isEmpty ? nil : data.unsupported
        )
    } catch {
        return .failed(error)
    }
}

let codexPersonal = await readCodex(
    accountID: "codex-personal",
    displayName: "Codex Personal",
    home: options.codexHomeA
)
let codexSecondary = await readCodex(
    accountID: "codex-secondary",
    displayName: "Codex Secondary",
    home: options.codexHomeB
)

if codexPersonal.planLabel == nil || codexSecondary.planLabel == nil {
    notes.append(
        "Sign each profile in separately: CODEX_HOME=<profile> codex login. "
            + "Never copy auth.json between profiles — refresh-token rotation breaks the copy."
    )
}

// MARK: Report

let report = SpikeReport(
    generatedAt: Date(),
    openrouter: openRouterSection,
    claude: claudeSection,
    codexPersonal: codexPersonal,
    codexSecondary: codexSecondary,
    bestFreeModels: ranked.map { category, model in
        SpikeReport.BestModel(
            category: category.rawValue,
            model: model.displayName,
            providerModelID: model.id,
            intelligence: model.benchmark?.intelligence,
            coding: model.benchmark?.coding,
            agentic: model.benchmark?.agentic,
            availability: model.availability?.percentage
        )
    },
    notes: notes
)

let encoder = DateFormatting.makeEncoder(prettyPrinted: true)
if let data = try? encoder.encode(report), let text = String(data: data, encoding: .utf8) {
    print(text)
} else {
    FileHandle.standardError.write(Data("failed to encode spike report\n".utf8))
    exit(1)
}
