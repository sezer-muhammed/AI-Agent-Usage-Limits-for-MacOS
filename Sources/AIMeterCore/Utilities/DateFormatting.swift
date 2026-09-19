import Foundation

public enum DateFormatting {
    /// Shared ISO-8601 coder for provider payloads and on-disk snapshots.
    /// Fractional seconds are optional because providers disagree about them.
    public static func iso8601(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    public static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// "3m ago" / "4h ago" — the freshness line every provider card carries.
    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// ISO-8601 in a given time zone, carrying the offset (`2026-09-19T20:52:32+03:00`).
    ///
    /// Stored data stays UTC — that is what a timestamp is for. This exists for
    /// output a person reads, where UTC is a needless translation step.
    public static func localISO8601String(
        _ date: Date,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    /// An encoder that writes dates in the machine's local time zone.
    /// For human-facing output only; persisted snapshots use `makeEncoder`.
    public static func makeLocalTimeEncoder(
        prettyPrinted: Bool = false,
        timeZone: TimeZone = .current
    ) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(localISO8601String(date, timeZone: timeZone))
        }
        return encoder
    }

    /// A JSON coder pair configured the same way everywhere, so a snapshot
    /// written by the app always decodes in the widget.
    public static func makeEncoder(prettyPrinted: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = iso8601(raw) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Bad date: \(raw)")
                )
            }
            return date
        }
        return decoder
    }
}
