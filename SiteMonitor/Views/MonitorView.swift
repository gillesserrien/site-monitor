import Combine
import SwiftUI

struct MonitorView: View {
    let monitor: SiteMonitor

    private enum FormMode: Hashable {
        case add
        case edit(Site)
    }

    @State private var formMode: FormMode?
    @State private var siteToRemove: Site.ID?
    @State private var showsActivity = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            activityLog
            Divider()
            footer
        }
        .frame(width: 360)
        .onAppear {
            monitor.refreshLoginItemStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            monitor.refreshLoginItemStatus()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch formMode {
        case .add:
            SiteForm(original: nil, onSave: addSite, onCancel: closeForm)
        case .edit(let site):
            SiteForm(original: site, onSave: updateSite, onCancel: closeForm)
                .id(site.id)
        case nil:
            siteList
        }
    }

    private func addSite(_ site: Site) {
        monitor.add(site)
        formMode = nil
    }

    private func updateSite(_ site: Site) {
        monitor.update(site)
        formMode = nil
    }

    private func closeForm() {
        formMode = nil
    }

    // MARK: - Header

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            HStack(spacing: 10) {
                Image(systemName: headerSymbol)
                    .font(.title2)
                    .foregroundStyle(headerColor)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary)
                        .font(.headline)
                    checkTimes(now: context.date)
                }

                Spacer()
                reloadButton(now: context.date)
            }
            .padding(12)
        }
    }

    private var headerSymbol: String {
        if monitor.isOffline {
            return "wifi.slash"
        }
        return monitor.overallStatus.symbolName
    }

    private var headerColor: Color {
        if monitor.isOffline {
            return .secondary
        }
        return monitor.overallStatus.color
    }

    private var summary: String {
        if monitor.isOffline {
            return "You're offline"
        }
        let total = monitor.sites.count
        if total == 0 {
            return "No sites yet"
        }

        let statuses = monitor.checkedStatuses
        let downCount = statuses.filter { status in status == .down }.count
        if downCount > 0 {
            return "\(downCount) of \(total) down"
        }

        let attentionCount = statuses.filter { status in status == .warning || status == .slow }.count
        if attentionCount > 0 {
            return "\(attentionCount) of \(total) need attention"
        }

        if statuses.count < total {
            return "Checking…"
        }
        if total == 1 {
            return "Your site is up"
        }
        return "All \(total) sites up"
    }

    private func checkTimes(now: Date) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 1) {
            GridRow {
                Text("Last check")
                if let lastCheck = monitor.lastCheck {
                    Text(Format.clockTime(lastCheck))
                } else {
                    Text("Not yet")
                }
            }
            GridRow {
                Text("Next check")
                Text(nextCheckText(now: now))
            }
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    private func nextCheckText(now: Date) -> String {
        if monitor.isChecking {
            return "Checking now…"
        }
        guard let nextCheck = monitor.nextCheck, nextCheck > now else {
            return "Soon"
        }
        return "in \(Format.duration(nextCheck.timeIntervalSince(now)))"
    }

    private func reloadButton(now: Date) -> some View {
        let secondsToWait = monitor.cooldownRemaining(at: now)
        return Button {
            monitor.reload()
        } label: {
            Group {
                if monitor.isChecking {
                    ProgressView()
                        .controlSize(.small)
                } else if secondsToWait > 0 {
                    Text("\(secondsToWait)s")
                        .monospacedDigit()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .frame(width: 30, height: 18)
        }
        .disabled(monitor.isChecking || secondsToWait > 0)
        .help(secondsToWait > 0 ? "You can check again in \(secondsToWait)s" : "Check all sites now")
    }

    // MARK: - Sites

    @ViewBuilder
    private var siteList: some View {
        if monitor.sites.isEmpty {
            Text("No sites yet. Add one below.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(24)
        } else if monitor.sites.count > 7 {
            ScrollView {
                rows
            }
            .frame(height: 400)
        } else {
            rows
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(monitor.sites) { site in
                if siteToRemove == site.id {
                    removalConfirmation(for: site)
                } else {
                    siteRow(site)
                }
            }
        }
        .padding(6)
    }

    private func siteRow(_ site: Site) -> some View {
        SiteRow(site: site, result: monitor.results[site.id], history: monitor.history[site.id] ?? [])
            .contextMenu {
                Button("Open in Browser") {
                    NSWorkspace.shared.open(site.url)
                }
                Button("Edit…") {
                    formMode = .edit(site)
                }
                Divider()
                Button("Remove…", role: .destructive) {
                    siteToRemove = site.id
                }
            }
    }

    private func removalConfirmation(for site: Site) -> some View {
        HStack(spacing: 8) {
            Text("Remove \(site.name)?")
                .fontWeight(.medium)
                .lineLimit(1)
            Spacer()
            Button("Cancel") {
                siteToRemove = nil
            }
            Button("Remove", role: .destructive) {
                monitor.remove(site)
                siteToRemove = nil
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    // MARK: - Activity log

    private var activityLog: some View {
        DisclosureGroup(isExpanded: $showsActivity) {
            VStack(alignment: .leading, spacing: 5) {
                if monitor.activity.isEmpty {
                    Text("Nothing has happened yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(monitor.activity) { entry in
                    activityRow(entry)
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        } label: {
            Text("Activity")
                .font(.subheadline.weight(.medium))
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation {
                        showsActivity.toggle()
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func activityRow(_ entry: ActivityEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Format.clockTime(entry.date))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(entry.siteName)
                .fontWeight(.medium)
            Text(entry.message)
                .foregroundStyle(entry.status.color)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                formMode = .add
            } label: {
                Label("Add site", systemImage: "plus")
            }
            .disabled(formMode != nil)

            Spacer()

            Menu {
                Picker("Check every", selection: intervalSelection) {
                    ForEach(SiteMonitor.intervalOptions, id: \.self) { interval in
                        Text(Format.checkInterval(interval))
                            .tag(interval)
                    }
                }
                Toggle("Open at Login", isOn: launchAtLoginSelection)
                Divider()
                Button("Quit Site Monitor") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings")
        }
        .padding(12)
    }

    private var intervalSelection: Binding<TimeInterval> {
        Binding(
            get: { monitor.checkInterval },
            set: { interval in monitor.setCheckInterval(interval) }
        )
    }

    private var launchAtLoginSelection: Binding<Bool> {
        Binding(
            get: { monitor.launchesAtLogin },
            set: { enabled in monitor.setLaunchesAtLogin(enabled) }
        )
    }
}

#if DEBUG
#Preview {
    MonitorView(monitor: .preview())
}
#endif
