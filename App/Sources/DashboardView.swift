import AIMeterCore
import SwiftUI

/// The main window: a standard macOS sidebar layout.
struct DashboardView: View {
    @Environment(AppState.self) private var state
    @State private var section: Section? = .overview

    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case usage = "Usage"
        case models = "Models"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .overview: "square.grid.2x2"
            case .usage: "gauge.with.dots.needle.33percent"
            case .models: "cpu"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch section ?? .overview {
            case .overview: OverviewSection()
            case .usage: UsageSection()
            case .models: ModelsSection()
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await state.refresh(force: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(state.isRefreshing)
                .keyboardShortcut("r")
            }
        }
        .navigationTitle("AI Meter")
    }
}

private struct OverviewSection: View {
    @Environment(AppState.self) private var state

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(state.accounts) { usage in
                    AccountCard(
                        title: state.displayName(for: usage),
                        usage: usage,
                        status: state.status(for: usage.accountID)
                    )
                    .padding(12)
                    .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
                }
            }
            .padding(16)
        }
        .overlay {
            if state.accounts.isEmpty {
                ContentUnavailableView(
                    "No data yet",
                    systemImage: "gauge",
                    description: Text("Configure a provider in Settings, then refresh.")
                )
            }
        }
    }
}

private struct UsageSection: View {
    @Environment(AppState.self) private var state

    var body: some View {
        List {
            ForEach(state.accounts) { usage in
                Section(state.displayName(for: usage)) {
                    if usage.windows.isEmpty {
                        Text("No quota data reported").foregroundStyle(.secondary)
                    }
                    ForEach(usage.windows) { window in
                        UsageBar(window: window).padding(.vertical, 4)
                    }
                    Text(Format.freshnessLabel(state.status(for: usage.accountID)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct ModelsSection: View {
    @Environment(AppState.self) private var state

    @State private var search = ""
    @State private var freeOnly = true

    private var rows: [AIModel] {
        state.models
            .filter { !freeOnly || $0.isFreeVariant }
            .filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        Table(rows) {
            TableColumn("Model", value: \.displayName)
            TableColumn("Provider", value: \.provider)
            TableColumn("Context") { model in
                Text(model.contextLength.map { "\($0 / 1000)K" } ?? "—").monospacedDigit()
            }
            // Benchmarks stay visibly empty rather than being invented.
            TableColumn("Intelligence") { model in
                Text(score(model.benchmark?.intelligence)).monospacedDigit()
            }
            TableColumn("Coding") { model in
                Text(score(model.benchmark?.coding)).monospacedDigit()
            }
            TableColumn("Agentic") { model in
                Text(score(model.benchmark?.agentic)).monospacedDigit()
            }
        }
        .searchable(text: $search, prompt: "Search models")
        .toolbar {
            ToolbarItem {
                Toggle("Free only", isOn: $freeOnly).toggleStyle(.switch)
            }
        }
    }

    private func score(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "—"
    }
}
