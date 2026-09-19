import AIMeterCore
import SwiftUI
import WidgetKit

/// Shared rendering rules for both families.
enum WidgetFormat {
    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    /// One vocabulary for every reset: "2h 4m" up close, a weekday further out.
    /// Mixing "1h 56m" with "Sun" in one column reads as two different units.
    static func reset(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }

        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "now" }

        if interval < 60 * 60 * 24 {
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60
            return hours > 0 ? "\(hours)h" : "\(minutes)m"
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

/// A percentage, a bar under it, and the reset time. The bar fills the space the
/// old layout wasted and makes the row scannable without reading numbers.
private struct WindowCell: View {
    let window: WidgetSnapshot.Window?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let window {
                HStack(spacing: 4) {
                    Text(WidgetFormat.percent(window.usedFraction))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(WidgetFormat.tint(window.usedFraction))

                    Spacer(minLength: 0)

                    Text(WidgetFormat.reset(window.resetsAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                Capsule()
                    .fill(.quaternary)
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(WidgetFormat.tint(window.usedFraction))
                                .frame(width: proxy.size.width * (window.usedFraction ?? 0))
                        }
                    }
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }
        }
    }
}

private struct AccountRow: View {
    let account: WidgetSnapshot.AccountUsage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 3) {
                Text(account.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Staleness is shown, never hidden.
                if account.isStale {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("stale")
                }
            }
            .frame(width: 92, alignment: .leading)

            if let detail = account.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                WindowCell(window: account.shortWindow).frame(maxWidth: .infinity)
                WindowCell(window: account.longWindow).frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        if let detail = account.detail { return "\(account.displayName), \(detail)" }

        var parts = [account.displayName]
        if let short = account.shortWindow {
            parts.append("5 hour \(WidgetFormat.percent(short.usedFraction)) used")
        }
        if let long = account.longWindow {
            parts.append("weekly \(WidgetFormat.percent(long.usedFraction)) used")
        }
        return parts.joined(separator: ", ")
    }
}

/// Calendar-widget cadence: a large accent title on top, then the content.
private struct WidgetTitle: View {
    let generatedAt: Date?
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("AI METER")
                .font(compact ? .subheadline.weight(.bold) : .title3.weight(.bold))
                .foregroundStyle(.tint)

            Spacer()

            if let generatedAt, !compact {
                // Labelled, so it does not read as a clock next to the weather
                // and calendar widgets.
                Text("updated \(generatedAt, style: .time)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct EmptyState: View {
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetTitle(generatedAt: nil, compact: compact)
            Text("Open AI Meter to load data")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The free-model line. With no benchmark source there is no "smartest" model to
/// name, so it reports the count instead of inventing a ranking.
private struct FreeModelLine: View {
    let snapshot: WidgetSnapshot
    var compact = false

    var body: some View {
        if let best = snapshot.bestFree["general"] {
            HStack(spacing: 4) {
                Text("Best free")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(best.name)
                    .font(.caption)
                    .lineLimit(1)
                if let score = best.score, !compact {
                    Spacer(minLength: 4)
                    Text(String(format: "%.1f", score))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        } else if let count = snapshot.freeModelCount {
            HStack(spacing: 4) {
                Text("\(count) free models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !compact {
                    Text("· no benchmark source")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct SmallWidgetView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        guard let snapshot, !snapshot.accounts.isEmpty else {
            return AnyView(EmptyState(compact: true))
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 5) {
                WidgetTitle(generatedAt: snapshot.generatedAt, compact: true)
                FreeModelLine(snapshot: snapshot, compact: true)

                Spacer(minLength: 2)

                // Too narrow for two columns: show whichever window is tightest.
                ForEach(snapshot.accounts) { account in
                    HStack(spacing: 6) {
                        Text(account.displayName)
                            .font(.caption2)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(WidgetFormat.percent(account.leadingWindow?.usedFraction))
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(
                                WidgetFormat.tint(account.leadingWindow?.usedFraction)
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                WidgetTitle(generatedAt: snapshot.generatedAt)
                FreeModelLine(snapshot: snapshot)

                // Column headers: the two numbers on a row are different windows,
                // which nothing said before.
                HStack(spacing: 10) {
                    Color.clear.frame(width: 92, height: 1)
                    Text("5-HOUR")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("WEEKLY")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)

                // Rows share the remaining height instead of leaving it empty.
                VStack(spacing: 0) {
                    ForEach(snapshot.accounts) { account in
                        AccountRow(account: account)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
    }
}
