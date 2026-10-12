import Charts
import SwiftUI

struct SiteRow: View {
    let site: Site
    let result: CheckResult?
    let history: [CheckResult]

    @State private var isHovered = false

    private var status: SiteStatus {
        result?.status ?? .unknown
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(status.color)
                .frame(width: 9, height: 9)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                titleLine
                detailLine
                if let result, result.status != .up {
                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(result.status.color)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isHovered ? Color.primary.opacity(0.07) : Color.clear, in: .rect(cornerRadius: 7))
        .contentShape(.rect)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            NSWorkspace.shared.open(site.url)
        }
        .help(tooltip)
    }

    private var titleLine: some View {
        HStack(spacing: 8) {
            Text(site.name)
                .fontWeight(.medium)
                .lineLimit(1)
            Spacer(minLength: 4)
            ResponseTimeChart(history: history)
                .frame(width: 56, height: 16)
            Text(Format.responseTime(result?.responseTime))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .trailing)
        }
    }

    private var detailLine: some View {
        HStack(spacing: 12) {
            Text(site.host)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let result {
                if let httpCode = result.httpCode {
                    Text("HTTP \(httpCode)")
                }
                Text("Checked \(Format.clockTime(result.date))")
                    .monospacedDigit()
            } else {
                Text("Waiting for first check")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var tooltip: String {
        var lines = ["Click to open \(site.url.absoluteString)"]
        if let expiry = result?.certificateExpiry {
            lines.append("SSL certificate valid until \(expiry.formatted(date: .long, time: .omitted))")
        }
        if !site.expectedText.isEmpty {
            lines.append("Looks for “\(site.expectedText)”")
        }
        if site.checksInertiaSSR {
            lines.append("Checks Inertia SSR")
        }
        return lines.joined(separator: "\n")
    }
}

struct ResponseTimeChart: View {
    let history: [CheckResult]

    private struct Point: Identifiable {
        let id: Int
        let milliseconds: Double
    }

    private var points: [Point] {
        var points: [Point] = []
        for (index, result) in history.enumerated() {
            if let responseTime = result.responseTime {
                points.append(Point(id: index, milliseconds: responseTime * 1000))
            }
        }
        return points
    }

    private var highestValue: Double {
        let values = points.map { point in point.milliseconds }
        return values.max() ?? 1
    }

    var body: some View {
        if points.count < 2 {
            Color.clear
        } else {
            Chart(points) { point in
                LineMark(x: .value("Check", point.id), y: .value("Response time", point.milliseconds))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(Color.secondary)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...(highestValue * 1.1))
        }
    }
}

#Preview {
    let monitor = SiteMonitor.preview()
    VStack(spacing: 0) {
        ForEach(monitor.sites) { site in
            SiteRow(site: site, result: monitor.results[site.id], history: monitor.history[site.id] ?? [])
        }
    }
    .padding(6)
    .frame(width: 360)
}
