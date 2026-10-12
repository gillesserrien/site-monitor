import Foundation

nonisolated enum Format {
    static func responseTime(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "–" }
        if seconds < 1 {
            let milliseconds = Int((seconds * 1000).rounded())
            return "\(milliseconds) ms"
        }
        return String(format: "%.1f s", seconds)
    }

    static func clockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 {
            return "\(total)s"
        }
        if total < 3600 {
            return "\(total / 60)m \(total % 60)s"
        }
        return "\(total / 3600)h \(total % 3600 / 60)m"
    }

    static func checkInterval(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total < 60 {
            return "\(total) seconds"
        }
        let minutes = total / 60
        if minutes == 1 {
            return "1 minute"
        }
        return "\(minutes) minutes"
    }
}
