import AIMeterCore
import SwiftUI

/// The popover behind the menu bar icon: a glance, not a dashboard.
/// Charts and tables live in the main window.
struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let best = state.snapshot.bestFree[.general] {
                Divider()
                bestFree(best)
            }

            Divider()

            if state.accounts.isEmpty {
                Text("No provider configured yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.accounts) { usage in
                    AccountCard(
                        title: state.displayName(for: usage),
                        usage: usage,
                        status: state.status(for: usage.accountID),
                        compact: true
                    )
                }
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("AI Meter").font(.headline)
            Spacer()
            Button {
                Task { await state.refresh(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(state.isRefreshing ? 360 : 0))
                    .animation(
                        state.isRefreshing
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: state.isRefreshing
                    )
            }
            .buttonStyle(.borderless)
            .disabled(state.isRefreshing)
            .help("Refresh now")
            .accessibilityLabel("Refresh now")
        }
    }

    private func bestFree(_ model: AIModel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("BEST FREE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(model.displayName).font(.callout)
            Text(scoreLine(model))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Says what is unknown instead of printing a made-up score.
    private func scoreLine(_ model: AIModel) -> String {
        guard let benchmark = model.benchmark, !benchmark.isEmpty else {
            return "Benchmark unavailable"
        }
        return [
            benchmark.intelligence.map { "Intel \(String(format: "%.1f", $0))" },
            benchmark.coding.map { "Code \(String(format: "%.1f", $0))" },
            model.availability?.percentage.map { "\(String(format: "%.1f", $0))%" },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var footer: some View {
        HStack {
            Button("Dashboard") { openWindow(id: "dashboard") }
            Spacer()
            SettingsLink { Text("Settings") }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.link)
        .font(.callout)
    }
}
