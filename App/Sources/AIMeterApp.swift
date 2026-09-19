import AIMeterCore
import SwiftUI

@main
struct AIMeterApp: App {
    @State private var state = AppState()

    init() {
        // Start the data layer at launch, not when the popover first opens:
        // a menu bar app that is never clicked still has to keep the widget
        // and the cache current.
        let state = self.state
        Task { await state.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(state)
                // Opening the menu refreshes only if the cache has aged out.
                .task { await state.refresh() }
        } label: {
            // Template rendering: the icon follows the menu bar's appearance.
            Image(systemName: menuBarSymbol)
                .accessibilityLabel("AI Meter")
        }
        .menuBarExtraStyle(.window)

        Window("AI Meter", id: "dashboard") {
            DashboardView()
                .environment(state)
                .frame(minWidth: 720, minHeight: 440)
        }
        .defaultSize(width: 900, height: 560)

        Settings {
            SettingsView().environment(state)
        }
    }

    /// A subtle state change at the thresholds, never a flashing icon.
    private var menuBarSymbol: String {
        guard let highest = state.highestUsage else { return "gauge.with.dots.needle.33percent" }
        if highest >= 0.95 { return "gauge.with.dots.needle.100percent" }
        if highest >= 0.80 { return "gauge.with.dots.needle.67percent" }
        return "gauge.with.dots.needle.33percent"
    }
}
