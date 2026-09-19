import AIMeterCore
import SwiftUI
import WidgetKit

/// Shared rendering rules for both families.
enum WidgetFormat {
    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    static func reset(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "now" }

        if interval < 60 * 60 * 20 {
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60
            return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    static func tint(_ fraction: Double?) -> Color {
        guard let fraction else { return .secondary }
        if fraction >= 0.95 { return .red }
        if fraction >= 0.80 { return .orange }
        return .accentColor
    }
}

private struct AccountRow: View {
    let account: WidgetSnapshot.AccountUsage
    var showReset = true

    var body: some View {
        HStack(spacing: 6) {
            Text(account.displayName)
                .font(.caption)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(WidgetFormat.percent(account.primaryUsage))
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(WidgetFormat.tint(account.primaryUsage))

            if showReset {
                Text(WidgetFormat.reset(account.resetsAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            // Staleness is shown, never hidden.
            if account.isStale {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("stale")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI METER").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            Text("Open the app to load data")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct SmallWidgetView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        guard let snapshot, !snapshot.accounts.isEmpty else {
            return AnyView(EmptyState())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 5) {
                Text("AI METER")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)

                if let best = snapshot.bestFree["general"] {
                    Text(best.name).font(.caption).lineLimit(1)
                }

                Spacer(minLength: 0)

                ForEach(snapshot.accounts.prefix(3)) { account in
                    AccountRow(account: account, showReset: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        )
    }
}

struct MediumWidgetView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        guard let snapshot, !snapshot.accounts.isEmpty else {
            return AnyView(EmptyState())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("AI METER")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(snapshot.generatedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !snapshot.bestFree.isEmpty {
                    ForEach(["general", "coding", "agentic"], id: \.self) { category in
                        if let model = snapshot.bestFree[category] {
                            HStack(spacing: 6) {
                                Text(category.capitalized)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 54, alignment: .leading)
                                Text(model.name).font(.caption).lineLimit(1)
                                Spacer(minLength: 4)
                                if let score = model.score {
                                    Text(String(format: "%.1f", score))
                                        .font(.caption2)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                    Divider()
                }

                ForEach(snapshot.accounts) { account in
                    AccountRow(account: account)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        )
    }
}
