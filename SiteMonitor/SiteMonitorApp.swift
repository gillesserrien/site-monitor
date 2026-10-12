import SwiftUI

@main
struct SiteMonitorApp: App {
    @State private var monitor: SiteMonitor

    init() {
        let monitor = SiteMonitor()
        monitor.start()
        _monitor = State(initialValue: monitor)
    }

    var body: some Scene {
        MenuBarExtra {
            MonitorView(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
