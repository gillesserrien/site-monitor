import Foundation
import Security
import Synchronization

nonisolated struct SiteChecker: Sendable {
    static let idleTimeout: TimeInterval = 15
    static let totalTimeout: TimeInterval = 30
    static let slowThreshold: TimeInterval = 2
    static let certificateWarningDays = 14

    private let session: URLSession
    private let certificates = CertificateCollector()

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Self.idleTimeout
        config.timeoutIntervalForResource = Self.totalTimeout
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpAdditionalHeaders = ["User-Agent": "SiteMonitor/1.0 (macOS)"]
        session = URLSession(configuration: config, delegate: certificates, delegateQueue: nil)
    }

    @concurrent
    func confirmedCheck(_ site: Site) async -> CheckResult {
        let firstResult = await check(site)
        // A timeout already waited long enough, so retrying it would hold up the whole check round.
        if firstResult.status != .down || firstResult.timedOut {
            return firstResult
        }
        // One failed request can be a blip; only report the site down when a retry fails too.
        try? await Task.sleep(for: .seconds(3))
        return await check(site)
    }

    @concurrent
    func check(_ site: Site) async -> CheckResult {
        let started = Date()
        do {
            let (data, response) = try await session.data(from: site.url)
            let responseTime = Date().timeIntervalSince(started)
            return evaluate(site, data: data, response: response, responseTime: responseTime)
        } catch let error as URLError {
            return failedResult(for: site, error: error)
        } catch {
            return CheckResult(date: .now, status: .down, message: error.localizedDescription)
        }
    }

    @concurrent
    func isOnline() async -> Bool {
        var request = URLRequest(url: URL(string: "https://www.apple.com/library/test/success.html")!)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            return http?.statusCode == 200
        } catch {
            return false
        }
    }

    private func evaluate(_ site: Site, data: Data, response: URLResponse, responseTime: TimeInterval) -> CheckResult {
        guard let http = response as? HTTPURLResponse else {
            return CheckResult(date: .now, status: .down, message: "No HTTP response")
        }

        var result = CheckResult(
            date: .now,
            status: .up,
            httpCode: http.statusCode,
            responseTime: responseTime,
            message: "OK",
            certificateExpiry: certificateExpiry(for: site, response: http)
        )

        if !(200..<400).contains(http.statusCode) {
            result.status = .down
            result.message = "HTTP \(http.statusCode)"
            return result
        }

        let html = String(decoding: data, as: UTF8.self)
        let isServerRendered = html.contains("data-server-rendered=\"true\"")
        let containsExpectedText = site.expectedText.isEmpty || html.localizedCaseInsensitiveContains(site.expectedText)

        if site.checksInertiaSSR && !isServerRendered {
            result.status = .warning
            result.message = "Inertia SSR is off, page renders in the browser"
        } else if !containsExpectedText {
            result.status = .warning
            result.message = "Text “\(site.expectedText)” not found"
        } else if let daysLeft = result.certificateDaysLeft, daysLeft < Self.certificateWarningDays {
            result.status = .warning
            result.message = "SSL certificate expires in \(daysLeft) days"
        } else if responseTime > Self.slowThreshold {
            result.status = .slow
            result.message = "Slow response"
        }
        return result
    }

    private func failedResult(for site: Site, error: URLError) -> CheckResult {
        var result = CheckResult(date: .now, status: .down, message: Self.describe(error))
        result.timedOut = (error.code == .timedOut)
        guard Self.isCertificateError(error.code) else {
            return result
        }
        if let host = site.url.host(), let expiry = certificates.expiry(for: host), expiry < .now {
            result.certificateExpiry = expiry
            result.message = "SSL certificate expired on \(expiry.formatted(date: .abbreviated, time: .omitted))"
        }
        return result
    }

    private func certificateExpiry(for site: Site, response: HTTPURLResponse) -> Date? {
        if let finalHost = response.url?.host(), let expiry = certificates.expiry(for: finalHost) {
            return expiry
        }
        guard let host = site.url.host() else { return nil }
        return certificates.expiry(for: host)
    }

    private static func isCertificateError(_ code: URLError.Code) -> Bool {
        switch code {
        case .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .timedOut:
            return "Server took too long to answer"
        case .cannotFindHost, .dnsLookupFailed:
            return "Domain not found (DNS)"
        case .cannotConnectToHost:
            return "Server refused the connection"
        case .networkConnectionLost:
            return "Connection dropped"
        case .notConnectedToInternet:
            return "No internet connection"
        case .serverCertificateHasBadDate:
            return "SSL certificate expired"
        case .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .secureConnectionFailed:
            return "SSL certificate problem"
        case .badServerResponse:
            return "Invalid response from server"
        default:
            return error.localizedDescription
        }
    }
}

nonisolated final class CertificateCollector: NSObject, URLSessionDelegate, Sendable {
    private let expiries = Mutex<[String: Date]>([:])

    func expiry(for host: String) -> Date? {
        expiries.withLock { stored in stored[host] }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = space.serverTrust,
           let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
           let certificate = chain.first,
           let expiry = Self.expiryDate(of: certificate) {
            expiries.withLock { stored in stored[space.host] = expiry }
        }
        // Observe only: macOS still performs normal certificate validation.
        completionHandler(.performDefaultHandling, nil)
    }

    private static func expiryDate(of certificate: SecCertificate) -> Date? {
        let key = kSecOIDX509V1ValidityNotAfter
        let values = SecCertificateCopyValues(certificate, [key] as CFArray, nil) as? [String: Any]
        guard let entry = values?[key as String] as? [String: Any],
              let seconds = entry[kSecPropertyKeyValue as String] as? NSNumber
        else { return nil }
        return Date(timeIntervalSinceReferenceDate: seconds.doubleValue)
    }
}
