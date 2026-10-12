import Foundation

nonisolated enum SiteStatus: Int, Comparable, Sendable {
    case unknown, up, slow, warning, down

    static func < (lhs: SiteStatus, rhs: SiteStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated struct CheckResult: Sendable {
    var date: Date
    var status: SiteStatus
    var httpCode: Int?
    var responseTime: TimeInterval?
    var message: String
    var certificateExpiry: Date?
    var timedOut = false

    var certificateDaysLeft: Int? {
        guard let certificateExpiry else { return nil }
        return Calendar.current.dateComponents([.day], from: date, to: certificateExpiry).day
    }
}

nonisolated struct ActivityEntry: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let siteName: String
    let status: SiteStatus
    let message: String
}
