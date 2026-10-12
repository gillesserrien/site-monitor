import AppKit
import SwiftUI

extension SiteStatus {
    var nsColor: NSColor {
        switch self {
        case .unknown: .systemGray
        case .up: .systemGreen
        case .slow, .warning: .systemOrange
        case .down: .systemRed
        }
    }

    var color: Color {
        Color(nsColor: nsColor)
    }

    var label: String {
        switch self {
        case .unknown: "Not checked yet"
        case .up: "Up"
        case .slow: "Slow"
        case .warning: "Needs attention"
        case .down: "Down"
        }
    }

    var symbolName: String {
        switch self {
        case .unknown: "circle.dashed"
        case .up: "checkmark.circle.fill"
        case .slow, .warning: "exclamationmark.circle.fill"
        case .down: "xmark.circle.fill"
        }
    }
}

struct MenuBarLabel: View {
    let monitor: SiteMonitor

    var body: some View {
        Image(nsImage: Self.image(status: monitor.overallStatus, offline: monitor.isOffline))
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if monitor.isOffline {
            return "Site Monitor: offline"
        }
        return "Site Monitor: \(monitor.overallStatus.label)"
    }

    static func image(status: SiteStatus, offline: Bool) -> NSImage {
        if offline {
            return symbolImage("wifi.slash", color: nil)
        }
        if status == .unknown {
            return symbolImage(status.symbolName, color: nil)
        }
        return symbolImage(status.symbolName, color: status.nsColor)
    }

    private static func symbolImage(_ name: String, color: NSColor?) -> NSImage {
        var configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let color {
            configuration = configuration.applying(NSImage.SymbolConfiguration(paletteColors: [.white, color]))
        }
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        let image = symbol?.withSymbolConfiguration(configuration) ?? NSImage()
        // Template images get recolored by the menu bar; colored icons must opt out.
        image.isTemplate = (color == nil)
        return image
    }
}
