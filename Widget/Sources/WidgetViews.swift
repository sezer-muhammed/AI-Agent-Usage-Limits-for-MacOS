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
    var nameWidth: CGFloat = 92

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
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
            .frame(width: nameWidth, alignment: .leading)

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
                    // "~" marks an estimated score, so it never passes for a
                    // measured benchmark result.
                    Text("\(best.isEstimate ? "~" : "")\(String(format: "%.1f", score))")
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

/// The catalog column: what OpenRouter offers right now, opposite the usage.
private struct CatalogColumn: View {
    let snapshot: WidgetSnapshot
    var showNewest = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let best = snapshot.bestFree["general"] {
                entry(
                    caption: "SMARTEST FREE",
                    name: best.name,
                    trailing: best.score.map {
                        // "~" marks an estimate, so it never reads as measured.
                        "\(best.isEstimate ? "~" : "")\(String(format: "%.1f", $0))"
                    }
                )
            }

            if let coding = snapshot.bestFree["coding"] {
                entry(
                    caption: "BEST CODING",
                    name: coding.name,
                    trailing: coding.score.map {
                        "\(coding.isEstimate ? "~" : "")\(String(format: "%.1f", $0))"
                    }
                )
            }

            if showNewest, let newest = snapshot.newestFreeModel {
                entry(
                    caption: "NEWEST FREE",
                    name: newest.name,
                    trailing: snapshot.newestFreeModelDate.map { Self.age($0) }
                )
            }

            Spacer(minLength: 0)

            if let count = snapshot.freeModelCount {
                Text("\(count) free models")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func entry(caption: String, name: String, trailing: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(caption)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 2)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 8, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Text(name)
                .font(.caption)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    /// "3d" / "2w" — how recently the model appeared.
    private static func age(_ date: Date, now: Date = Date()) -> String {
        let days = Int(now.timeIntervalSince(date) / 86_400)
        if days < 1 { return "today" }
        if days < 7 { return "\(days)d" }
        return "\(days / 7)w"
    }
}

/// Usage on the left, catalog on the right, at the requested 2:1 ratio.
private struct SplitLayout<Usage: View, Catalog: View>: View {
    @ViewBuilder var usage: Usage
    @ViewBuilder var catalog: Catalog

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            usage.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(2)

            Divider()

            catalog.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)
        }
    }
}

/// Splits a width 2:1 without hard-coding pixel widths.
private struct ProportionalSplit<Usage: View, Catalog: View>: View {
    let ratio: CGFloat
    @ViewBuilder var usage: Usage
    @ViewBuilder var catalog: Catalog

    var body: some View {
        GeometryReader { proxy in
            let dividerSpace: CGFloat = 21
            let usableWidth = max(proxy.size.width - dividerSpace, 0)
            let usageWidth = usableWidth * ratio / (ratio + 1)

            HStack(alignment: .top, spacing: 8) {
                usage.frame(width: usageWidth, alignment: .topLeading)
                Divider()
                catalog.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
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

                ProportionalSplit(ratio: 2) {
                    VStack(alignment: .leading, spacing: 4) {
                        ColumnHeaders(nameWidth: 66)
                        VStack(spacing: 0) {
                            ForEach(snapshot.accounts) { account in
                                AccountRow(account: account, nameWidth: 66)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                    }
                } catalog: {
                    // The medium widget is too short for three catalog entries.
                    CatalogColumn(snapshot: snapshot, showNewest: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
    }
}

struct LargeWidgetView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        guard let snapshot, !snapshot.accounts.isEmpty else {
            return AnyView(EmptyState())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                WidgetTitle(generatedAt: snapshot.generatedAt)

                ProportionalSplit(ratio: 2) {
                    VStack(alignment: .leading, spacing: 6) {
                        ColumnHeaders(nameWidth: 92)
                        VStack(spacing: 0) {
                            ForEach(snapshot.accounts) { account in
                                AccountRow(account: account, nameWidth: 92)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                    }
                } catalog: {
                    CatalogColumn(snapshot: snapshot)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
    }
}

/// Column headers: the two numbers on a row are different windows, which
/// nothing said before they existed.
private struct ColumnHeaders: View {
    let nameWidth: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: nameWidth, height: 1)
            Text("5-HOUR").frame(maxWidth: .infinity, alignment: .leading)
            Text("WEEKLY").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.tertiary)
    }
}
