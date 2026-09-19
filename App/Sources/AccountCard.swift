import AIMeterCore
import SwiftUI

/// One account: its windows, its spend, and how fresh the data is.
///
/// A provider that failed keeps showing its cached numbers; only the freshness
/// line changes. Empty error UI never replaces useful data.
struct AccountCard: View {
    let title: String
    let usage: UsageSnapshot?
    let status: ProviderStatus?
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(compact ? .subheadline.weight(.medium) : .headline)

                if let plan = usage?.planLabel {
                    Text(plan)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if status?.lastErrorDescription != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(status?.lastErrorDescription ?? "")
                        .accessibilityLabel("Refresh failed")
                }
            }

            if let usage, !usage.windows.isEmpty {
                ForEach(usage.windows) { window in
                    UsageBar(window: window, compact: compact)
                }
            } else {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let spend = usage?.spendTodayUSD ?? usage?.creditsRemainingUSD {
                HStack(spacing: 4) {
                    Text(usage?.spendTodayUSD != nil ? "Today" : "Credits")
                    Text(Format.usd(spend)).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(Format.freshnessLabel(status))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Says what is missing rather than implying a zero quota.
    private var emptyMessage: String {
        if let error = status?.lastErrorDescription { return error }
        return "No quota data reported"
    }
}
