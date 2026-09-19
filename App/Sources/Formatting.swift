import AIMeterCore
import Foundation
import SwiftUI

/// Presentation helpers shared by the menu bar, the dashboard and the widget.
enum Format {
    /// "72%" — always rendered as text, never as colour alone.
    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    /// "1h 42m" / "Tue" — how long until a window resets, in local time.
    static func untilReset(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }

        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "now" }

        if interval < 60 * 60 * 20 {
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60
            return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = interval < 60 * 60 * 24 * 6 ? "EEE HH:mm" : "d MMM"
        return formatter.string(from: date)
    }

    static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date, date != .distantPast else { return "never" }
        return DateFormatting.relative(date, now: now)
    }

    static func usd(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "—"
    }

    /// Warning at 80%, critical at 95% — thresholds from the spec.
    static func tint(for fraction: Double?) -> Color {
        guard let fraction else { return .secondary }
        if fraction >= 0.95 { return .red }
        if fraction >= 0.80 { return .orange }
        return .accentColor
    }

    static func freshnessLabel(_ status: ProviderStatus?, now: Date = Date()) -> String {
        guard let status else { return "Not configured" }

        if let error = status.lastErrorDescription {
            guard let lastSuccess = status.lastSuccessAt else { return error }
            return "Last update \(relative(lastSuccess, now: now)) · refresh failed"
        }

        guard let lastSuccess = status.lastSuccessAt else { return "Not configured" }

        let freshness = Freshness.of(lastSuccess, now: now)
        let age = relative(lastSuccess, now: now)
        return switch freshness {
        case .fresh: "Updated \(age)"
        case .slightlyStale: "Updated \(age)"
        case .stale: "Updated \(age) · stale"
        }
    }
}
