import AIMeterCore
import SwiftUI
import WidgetKit

/// The widget performs no networking and never opens the history database.
/// It reads one small JSON snapshot the app publishes, and nothing else.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct AIMeterWidgetProvider: TimelineProvider {
    private var reader: WidgetSnapshotWriter? {
        WidgetSnapshotWriter(appGroupIdentifier: "group.com.sezer-muhammed.aimeter")
    }

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: try? reader?.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: try? reader?.read())
        // The app reloads timelines when it publishes; this is only a backstop,
        // deliberately far apart so an idle widget costs nothing.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct AIMeterWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        switch family {
        case .systemSmall: SmallWidgetView(snapshot: entry.snapshot)
        case .systemLarge: LargeWidgetView(snapshot: entry.snapshot)
        default: MediumWidgetView(snapshot: entry.snapshot)
        }
    }
}

@main
struct AIMeterWidgetBundle: WidgetBundle {
    var body: some Widget {
        AIMeterWidget()
    }
}

struct AIMeterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AIMeterWidget", provider: AIMeterWidgetProvider()) { entry in
            AIMeterWidgetEntryView(entry: entry)
                // Roughly 30% transparent, so the desktop shows through. The
                // semantic background colour keeps it correct in both themes.
                .containerBackground(for: .widget) {
                    Color(nsColor: .windowBackgroundColor).opacity(0.7)
                }
        }
        .configurationDisplayName("AI Meter")
        .description("AI usage limits and the best free models, at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
