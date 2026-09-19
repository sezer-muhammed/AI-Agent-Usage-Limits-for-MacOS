import AIMeterCore
import SwiftUI

/// One quota window: label, bar, explicit percentage, reset time.
///
/// The percentage is always spelled out — state is never carried by colour
/// alone — and the whole row reads as one sentence to VoiceOver.
struct UsageBar: View {
    let window: RateLimitWindow
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(window.label)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(Format.percent(window.usedFraction))
                    .font(compact ? .caption : .subheadline)
                    .monospacedDigit()

                Text(Format.untilReset(window.resetsAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            ProgressView(value: window.usedFraction ?? 0)
                .progressViewStyle(.linear)
                .tint(Format.tint(for: window.usedFraction))
                .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var sentence = "\(window.label), \(Format.percent(window.usedFraction)) used"
        if let resetsAt = window.resetsAt {
            sentence += ", resets in \(Format.untilReset(resetsAt))"
        }
        return sentence
    }
}
