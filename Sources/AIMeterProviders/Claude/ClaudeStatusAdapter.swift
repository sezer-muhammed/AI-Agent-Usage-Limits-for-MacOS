import AIMeterCore
import Foundation

/// Normalizes sanitized Claude telemetry into a `UsageSnapshot`.
///
/// Claude usage is event-driven: the bridge only writes when Claude Code runs
/// the status line. `capturedAt` therefore carries real meaning and the UI must
/// show it — this adapter never presents the value as live.
public struct ClaudeStatusAdapter: UsageProvider {
    public let providerID: Provider.ID = Provider.claude.id
    public let accountID: String

    private let reader: ClaudeBridgeReader

    public init(accountID: String = "claude", reader: ClaudeBridgeReader = ClaudeBridgeReader()) {
        self.accountID = accountID
        self.reader = reader
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let telemetry = try reader.read()

        var windows: [RateLimitWindow] = []
        if let limits = telemetry.rateLimits {
            if let window = limits.fiveHour {
                windows.append(
                    Self.window(
                        window,
                        id: "\(accountID).five-hour",
                        kind: .fiveHour,
                        label: "5-hour window",
                        durationMinutes: 300
                    )
                )
            }
            if let window = limits.sevenDay {
                windows.append(
                    Self.window(
                        window,
                        id: "\(accountID).seven-day",
                        kind: .weekly,
                        label: "7-day window",
                        durationMinutes: 60 * 24 * 7
                    )
                )
            }
            if let window = limits.spendLimit {
                windows.append(
                    Self.window(
                        window,
                        id: "\(accountID).spend-limit",
                        kind: .custom,
                        label: "Spend limit",
                        durationMinutes: nil
                    )
                )
            }
        }

        return UsageSnapshot(
            provider: .claude,
            accountID: accountID,
            // The telemetry's own capture time, not now: this is cached data.
            capturedAt: telemetry.capturedAt,
            windows: windows,
            activeModelID: telemetry.model?.id
        )
    }

    /// Claude telemetry goes stale faster than a polled API, so it uses its own
    /// thresholds.
    public func freshness(now: Date = Date()) -> Freshness? {
        guard let telemetry = try? reader.read() else { return nil }
        return Freshness.of(telemetry.capturedAt, now: now, thresholds: .claude)
    }

    private static func window(
        _ window: ClaudeTelemetry.Window,
        id: String,
        kind: RateLimitWindow.Kind,
        label: String,
        durationMinutes: Int?
    ) -> RateLimitWindow {
        RateLimitWindow(
            id: id,
            kind: kind,
            usedFraction: window.usedPercentage.map { $0 / 100 },
            resetsAt: window.resetsAt,
            durationMinutes: durationMinutes,
            label: label
        )
    }
}
