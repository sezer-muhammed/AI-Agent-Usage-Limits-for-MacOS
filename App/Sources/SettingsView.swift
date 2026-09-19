import AIMeterCore
import AIMeterProviders
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            OpenRouterSettings()
                .tabItem { Label("OpenRouter", systemImage: "key") }
            ClaudeSettings()
                .tabItem { Label("Claude", systemImage: "sparkle") }
            CodexSettings()
                .tabItem { Label("Codex", systemImage: "terminal") }
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "lock") }
        }
        .frame(width: 460, height: 320)
    }
}

private struct GeneralSettings: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle("Launch AI Meter at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    // SMAppService, not a hand-installed LaunchAgent.
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        }
        .formStyle(.grouped)
    }
}

private struct OpenRouterSettings: View {
    @Environment(AppState.self) private var state

    @State private var key = ""
    @State private var storedHint: String?
    @State private var message: String?

    var body: some View {
        Form {
            Section("API key") {
                // A stored key is never readable back — only a redacted hint.
                if let storedHint {
                    LabeledContent("Stored", value: storedHint)
                }

                SecureField("sk-or-…", text: $key)

                HStack {
                    Button("Save and test") { Task { await save() } }
                        .disabled(key.isEmpty)
                    Button("Remove") { Task { await remove() } }
                        .disabled(storedHint == nil)
                }

                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await loadHint() }
    }

    private func loadHint() async {
        let stored = try? await state.environment.keychain.secret(for: .openRouterAPIKey)
        storedHint = stored.map { KeychainStore.redacted($0) }
    }

    private func save() async {
        let entered = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await state.environment.keychain.setSecret(entered, for: .openRouterAPIKey)
            await state.environment.openRouterKey.invalidate()
            _ = try await state.environment.openRouterClient.testConnection()
            message = "Connected."
            key = ""
            await loadHint()
            await state.refresh(force: true)
        } catch {
            message = (error as? ProviderError)?.errorDescription ?? error.localizedDescription
            await loadHint()
        }
    }

    private func remove() async {
        try? await state.environment.keychain.deleteSecret(for: .openRouterAPIKey)
        await state.environment.openRouterKey.invalidate()
        storedHint = nil
        message = "Key removed."
    }
}

private struct ClaudeSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            LabeledContent("Claude Code", value: claudeInstalled ? "Detected" : "Not found")
            LabeledContent("Bridge telemetry", value: bridgeState)

            Section {
                Text(
                    "Claude usage comes from Claude Code's status-line telemetry. "
                        + "AI Meter never reads Claude credentials."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("Install the bridge with:\naimeter-spike --install-claude-bridge")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    private var claudeInstalled: Bool {
        ExecutableLocator().locate("claude") != nil
    }

    private var bridgeState: String {
        guard state.environment.claudeReader.isInstalled else { return "Not installed" }
        guard let telemetry = try? state.environment.claudeReader.read() else {
            return "Unreadable"
        }
        return "Updated \(Format.relative(telemetry.capturedAt))"
    }
}

private struct CodexSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            ForEach(state.environment.codexAccounts, id: \.accountID) { account in
                Section(account.displayName) {
                    LabeledContent("Profile", value: account.profilePath)
                        .font(.caption)
                    LabeledContent("Status", value: statusText(account.accountID))
                    Text("Sign in with:\nCODEX_HOME=\(account.profilePath) codex login")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func statusText(_ accountID: String) -> String {
        guard let status = state.status(for: accountID) else { return "Not refreshed yet" }
        return status.isHealthy ? "Connected" : (status.lastErrorDescription ?? "Unavailable")
    }
}

private struct PrivacySettings: View {
    var body: some View {
        Form {
            Section {
                privacyLine("OpenRouter API key", "stored in the macOS Keychain")
                privacyLine("Claude credentials", "never read")
                privacyLine("Codex credentials", "never copied")
                privacyLine("Usage history", "stored only on this Mac")
                privacyLine("Widget", "receives a sanitized local snapshot only")
                privacyLine("Telemetry", "none")
            }
        }
        .formStyle(.grouped)
    }

    private func privacyLine(_ title: String, _ detail: String) -> some View {
        LabeledContent(title, value: detail)
    }
}
