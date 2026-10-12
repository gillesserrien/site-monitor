import AppKit
import Observation
import ServiceManagement

@Observable
final class SiteMonitor {
    static let reloadCooldown: TimeInterval = 5
    static let intervalOptions: [TimeInterval] = [30, 60, 300, 900]
    private static let offlineRetryInterval: TimeInterval = 30
    private static let historyLength = 30
    private static let activityLength = 10

    private(set) var sites: [Site]
    private(set) var results: [Site.ID: CheckResult] = [:]
    private(set) var history: [Site.ID: [CheckResult]] = [:]
    private(set) var activity: [ActivityEntry] = []
    private(set) var lastCheck: Date?
    private(set) var nextCheck: Date?
    private(set) var isChecking = false
    private(set) var isOffline = false
    private(set) var cooldownUntil: Date?
    private(set) var checkInterval: TimeInterval
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled

    @ObservationIgnored private let checker = SiteChecker()
    @ObservationIgnored private let store: SiteStore
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var sleepObservers: [any NSObjectProtocol] = []

    init(sites: [Site]? = nil) {
        let store = SiteStore()
        self.store = store

        let savedInterval = UserDefaults.standard.double(forKey: "checkInterval")
        checkInterval = savedInterval > 0 ? savedInterval : 60

        if let sites {
            self.sites = sites
        } else if let savedSites = store.load() {
            self.sites = savedSites
        } else {
            self.sites = Site.defaults
        }
    }

    var checkedStatuses: [SiteStatus] {
        sites.compactMap { site in results[site.id]?.status }
    }

    var overallStatus: SiteStatus {
        checkedStatuses.max() ?? .unknown
    }

    func start() {
        store.save(sites)
        Notifier.shared.requestPermission()
        observeSleepAndWake()
        scheduleChecks(startingIn: 0)
    }

    private func observeSleepAndWake() {
        let center = NSWorkspace.shared.notificationCenter
        let sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopChecks()
            }
        }
        let wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Wi-Fi needs a few seconds to reconnect after waking up.
            MainActor.assumeIsolated {
                self?.scheduleChecks(startingIn: 5)
            }
        }
        sleepObservers = [sleepObserver, wakeObserver]
    }

    // MARK: - Checking

    func cooldownRemaining(at date: Date) -> Int {
        guard let cooldownUntil else { return 0 }
        let secondsLeft = cooldownUntil.timeIntervalSince(date).rounded(.up)
        return max(0, Int(secondsLeft))
    }

    func reload() {
        if isChecking || cooldownRemaining(at: .now) > 0 {
            return
        }
        cooldownUntil = .now.addingTimeInterval(Self.reloadCooldown)
        scheduleChecks(startingIn: 0)
    }

    func setCheckInterval(_ interval: TimeInterval) {
        checkInterval = interval
        UserDefaults.standard.set(interval, forKey: "checkInterval")
        if isChecking {
            // The running loop picks up the new interval as soon as this check finishes.
            return
        }
        let next = (lastCheck ?? .now).addingTimeInterval(interval)
        scheduleChecks(startingIn: max(0, next.timeIntervalSinceNow))
    }

    private func scheduleChecks(startingIn delay: TimeInterval) {
        let previousLoop = loop
        previousLoop?.cancel()
        loop = Task { [weak self] in
            // A cancelled check needs a moment to unwind; starting earlier would skip our first check.
            await previousLoop?.value
            var wait = delay
            while !Task.isCancelled {
                self?.nextCheck = .now.addingTimeInterval(wait)
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled, let self else { return }
                await self.checkAll()
                wait = self.waitUntilNextCheck
            }
        }
    }

    private func stopChecks() {
        loop?.cancel()
        nextCheck = nil
    }

    private var waitUntilNextCheck: TimeInterval {
        if isOffline {
            return min(Self.offlineRetryInterval, checkInterval)
        }
        return checkInterval
    }

    func checkAll() async {
        if isChecking {
            return
        }
        isChecking = true
        defer { isChecking = false }

        await runChecks(on: sites)
        if !Task.isCancelled {
            lastCheck = .now
        }
    }

    private func runChecks(on targets: [Site]) async {
        let checker = self.checker
        let freshResults = await withTaskGroup(of: (Site.ID, CheckResult).self) { group in
            for site in targets {
                group.addTask {
                    let result = await checker.confirmedCheck(site)
                    return (site.id, result)
                }
            }
            var collected: [Site.ID: CheckResult] = [:]
            for await (siteID, result) in group {
                collected[siteID] = result
            }
            return collected
        }
        if Task.isCancelled {
            return
        }

        // Only a site that didn't answer at all could mean our own internet is down.
        let somethingUnreachable = freshResults.values.contains { result in
            result.status == .down && result.httpCode == nil
        }
        if somethingUnreachable {
            let online = await checker.isOnline()
            if Task.isCancelled {
                return
            }
            if !online {
                markOffline()
                return
            }
        }
        if isOffline {
            isOffline = false
            log(siteName: "Your Mac", status: .up, message: "Back online")
        }

        for site in targets {
            // Skip results for sites that were removed or edited while we were checking.
            let currentSite = sites.first { candidate in candidate.id == site.id }
            if let result = freshResults[site.id], currentSite == site {
                record(result, for: site)
            }
        }
    }

    private func markOffline() {
        if !isOffline {
            log(siteName: "Your Mac", status: .unknown, message: "Offline, checks paused")
        }
        isOffline = true
    }

    private func record(_ result: CheckResult, for site: Site) {
        let previousStatus = results[site.id]?.status ?? .unknown
        results[site.id] = result

        var siteHistory = history[site.id] ?? []
        siteHistory.append(result)
        history[site.id] = Array(siteHistory.suffix(Self.historyLength))

        if previousStatus == result.status {
            return
        }
        logChange(result, for: site)
        notifyChange(from: previousStatus, to: result, for: site)
    }

    private func logChange(_ result: CheckResult, for site: Site) {
        let message: String
        if result.status == .up {
            message = "Up in \(Format.responseTime(result.responseTime))"
        } else {
            message = result.message
        }
        log(siteName: site.name, status: result.status, message: message)
    }

    private func notifyChange(from previousStatus: SiteStatus, to result: CheckResult, for site: Site) {
        let wasFailing = previousStatus == .down || previousStatus == .warning

        if result.status == .down {
            Notifier.shared.send(title: "\(site.name) is down", subtitle: site.host, body: result.message)
        } else if result.status == .warning {
            Notifier.shared.send(title: "\(site.name) needs attention", subtitle: site.host, body: result.message)
        } else if wasFailing {
            let body = "Responded in \(Format.responseTime(result.responseTime))"
            Notifier.shared.send(title: "\(site.name) is back up", subtitle: site.host, body: body)
        }
    }

    private func log(siteName: String, status: SiteStatus, message: String) {
        let entry = ActivityEntry(date: .now, siteName: siteName, status: status, message: message)
        activity.insert(entry, at: 0)
        if activity.count > Self.activityLength {
            activity.removeLast(activity.count - Self.activityLength)
        }
    }

    // MARK: - Managing sites

    func add(_ site: Site) {
        sites.append(site)
        store.save(sites)
        Task {
            await runChecks(on: [site])
        }
    }

    func update(_ site: Site) {
        guard let index = sites.firstIndex(where: { current in current.id == site.id }) else { return }
        sites[index] = site
        results[site.id] = nil
        history[site.id] = nil
        store.save(sites)
        Task {
            await runChecks(on: [site])
        }
    }

    func remove(_ site: Site) {
        sites.removeAll { current in current.id == site.id }
        results[site.id] = nil
        history[site.id] = nil
        store.save(sites)
    }

    // MARK: - Settings

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Could not change login item: \(error)")
        }
        refreshLoginItemStatus()
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func refreshLoginItemStatus() {
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }
}

#if DEBUG
extension SiteMonitor {
    static func preview() -> SiteMonitor {
        let monitor = SiteMonitor(sites: Site.defaults)
        let now = Date.now
        let samples: [(status: SiteStatus, responseTime: TimeInterval, message: String)] = [
            (.up, 0.21, "OK"),
            (.slow, 2.4, "Slow response"),
            (.warning, 0.52, "Inertia SSR is off, page renders in the browser"),
        ]

        for (site, sample) in zip(monitor.sites, samples) {
            let result = CheckResult(
                date: now.addingTimeInterval(-12),
                status: sample.status,
                httpCode: 200,
                responseTime: sample.responseTime,
                message: sample.message,
                certificateExpiry: now.addingTimeInterval(60 * 60 * 24 * 60)
            )
            monitor.results[site.id] = result
            monitor.history[site.id] = (0..<20).map { minute in
                var point = result
                point.responseTime = sample.responseTime * Double.random(in: 0.7...1.3)
                point.date = now.addingTimeInterval(Double(minute - 20) * 60)
                return point
            }
        }

        monitor.lastCheck = now.addingTimeInterval(-12)
        monitor.nextCheck = now.addingTimeInterval(48)
        monitor.log(siteName: "EHALE", status: .slow, message: "Slow response")
        monitor.log(siteName: "ACGT17", status: .warning, message: "Inertia SSR is off, page renders in the browser")
        return monitor
    }
}
#endif
