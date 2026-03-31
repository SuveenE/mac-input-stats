import Charts
import Sparkle
import SwiftUI

// MARK: - Panel Shape

private struct PanelShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: 10, style: .continuous)
    }
}

// MARK: - Chart Range

enum ChartRange: String, CaseIterable {
    case oneDay = "1d"
    case sevenDays = "7d"
    case fourteenDays = "14d"
    case thirtyDays = "30d"

    var dayCount: Int {
        switch self {
        case .oneDay: return 1
        case .sevenDays: return 7
        case .fourteenDays: return 14
        case .thirtyDays: return 30
        }
    }

    var label: String { rawValue }
}

// MARK: - Main View

struct MenuBarView: View {
    @ObservedObject var store: StatsStore
    @ObservedObject var micMonitor: SpeechDetector
    var updater: SPUUpdater
    var onClose: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    @State private var hoveredDate: String?
    @State private var expandedApp: String?
    @AppStorage("statsExpanded") private var statsExpanded = false
    @AppStorage("chartRange") private var chartRange: ChartRange = .sevenDays

    private let panelWidth: CGFloat = 340

    private var liveTalkTime: String {
        let total = store.today.talkDurationSeconds + micMonitor.ongoingSessionSeconds
        return AppStats.formatDuration(total)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            todayStats
            Divider().padding(.horizontal, 12)
            topAppsSection
            Divider().padding(.horizontal, 12)
            statsDisclosure
            if statsExpanded {
                weeklyChart
                Divider().padding(.horizontal, 12)
                talkTimeSection
            }
            Divider().padding(.horizontal, 12)
            footerBar
        }
        .frame(width: panelWidth)
        .background(.regularMaterial, in: PanelShape())
        .overlay {
            PanelShape()
                .stroke(Color.black.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .animation(.easeInOut(duration: 0.2), value: statsExpanded)
        .animation(.easeInOut(duration: 0.2), value: chartRange)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("Input Stats")
                .font(.title3.bold())
            #if DEBUG
            Text("DEV")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.orange, in: Capsule())
            #endif
            Spacer()
            Text(todayDateString)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.55))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Today Stats

    private var todayStats: some View {
        VStack(spacing: 2) {
            statRow(icon: "keyboard",
                    value: "\(store.today.keystrokes)",
                    label: "Keystrokes")
            statRow(icon: "cursorarrow.click.2",
                    value: "\(store.today.pointerClicks)",
                    label: "Clicks")
            statRow(icon: "scroll",
                    value: "\(store.today.scrollEvents)",
                    label: "Scrolls")
            statRow(icon: micMonitor.micInUse ? "mic.fill" : "waveform",
                    value: liveTalkTime,
                    label: "Talk time")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func statRow(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.blue, in: Circle())

            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())

            Spacer()

            Text(label)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.55))
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
    }

    // MARK: - Top Apps

    private var topAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Apps by Screen Time")
                .font(.headline)
                .padding(.horizontal, 6)
                .padding(.bottom, 2)

            let apps = Array(store.today.topApps.prefix(5))
            if apps.isEmpty {
                Text("No activity yet")
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.55))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
            } else {
                let maxTime = apps.first?.stats.screenTimeSeconds ?? 1
                ForEach(apps, id: \.name) { app in
                    appRow(name: app.name, stats: app.stats, maxScreenTime: maxTime)
                }
                .onAppear {
                    if expandedApp == nil, let first = apps.first {
                        expandedApp = first.name
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func appRow(name: String, stats: AppStats, maxScreenTime: Double) -> some View {
        let isExpanded = expandedApp == name

        return VStack(spacing: 3) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedApp = isExpanded ? nil : name
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.55))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text(name)
                        .font(.body)
                        .lineLimit(1)
                    Spacer()
                    if stats.talkDurationSeconds > 0 {
                        Text(stats.formattedTalkTime)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.12), in: Capsule())
                    }
                    Text(stats.formattedScreenTime)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.primary.opacity(0.55))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            GeometryReader { geo in
                let ratio = CGFloat(stats.screenTimeSeconds) / CGFloat(Swift.max(maxScreenTime, 1))
                RoundedRectangle(cornerRadius: 2)
                    .fill(.blue.opacity(0.25))
                    .frame(width: geo.size.width * ratio, height: 3)
            }
            .frame(height: 3)

            if isExpanded {
                HStack(spacing: 16) {
                    appDetailItem(icon: "keyboard", value: "\(stats.keystrokes)")
                    appDetailItem(icon: "cursorarrow.click.2", value: "\(stats.pointerClicks)")
                    appDetailItem(icon: "scroll", value: "\(stats.scrollEvents)")
                    if stats.talkDurationSeconds > 0 {
                        appDetailItem(icon: "waveform", value: stats.formattedTalkTime)
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    private func appDetailItem(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.primary.opacity(0.55))
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary.opacity(0.55))
        }
    }

    // MARK: - Stats Disclosure

    private var statsDisclosure: some View {
        Button {
            statsExpanded.toggle()
        } label: {
            HStack {
                Text("Trends")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.55))
                    .rotationEffect(.degrees(statsExpanded ? 90 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Range Chart

    private var rangePickerBar: some View {
        HStack(spacing: 0) {
            ForEach(ChartRange.allCases, id: \.self) { range in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        chartRange = range
                        hoveredDate = nil
                    }
                } label: {
                    Text(range.label)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .foregroundStyle(chartRange == range ? .white : .primary.opacity(0.55))
                        .background(
                            chartRange == range
                                ? Color.blue
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var weeklyChart: some View {
        let days = store.recentDays(count: chartRange.dayCount)
        let dateLabels = days.map { shortDate($0.date) }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                rangePickerBar
                Spacer()
                legendDot(color: .blue, label: "Keys")
                legendDot(color: .orange, label: "Clicks")
                legendDot(color: .green, label: "Scrolls")
            }
            .padding(.horizontal, 6)

            Chart {
                ForEach(days) { day in
                    let d = shortDate(day.date)
                    let isHovered = hoveredDate == d

                    LineMark(x: .value("Date", d), y: .value("Count", day.keystrokes), series: .value("Metric", "Keystrokes"))
                        .foregroundStyle(by: .value("Metric", "Keystrokes"))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", d), y: .value("Count", day.keystrokes))
                        .foregroundStyle(by: .value("Metric", "Keystrokes"))
                        .symbolSize(isHovered ? 50 : 20)
                        .annotation(position: .top, spacing: 2) {
                            if isHovered {
                                Text("\(day.keystrokes)")
                                    .font(.system(size: 8).bold())
                                    .foregroundStyle(.blue)
                            }
                        }

                    LineMark(x: .value("Date", d), y: .value("Count", day.pointerClicks), series: .value("Metric", "Clicks"))
                        .foregroundStyle(by: .value("Metric", "Clicks"))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", d), y: .value("Count", day.pointerClicks))
                        .foregroundStyle(by: .value("Metric", "Clicks"))
                        .symbolSize(isHovered ? 50 : 20)
                        .annotation(position: .top, spacing: 2) {
                            if isHovered {
                                Text("\(day.pointerClicks)")
                                    .font(.system(size: 8).bold())
                                    .foregroundStyle(.orange)
                            }
                        }

                    LineMark(x: .value("Date", d), y: .value("Count", day.scrollEvents), series: .value("Metric", "Scrolls"))
                        .foregroundStyle(by: .value("Metric", "Scrolls"))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", d), y: .value("Count", day.scrollEvents))
                        .foregroundStyle(by: .value("Metric", "Scrolls"))
                        .symbolSize(isHovered ? 50 : 20)
                        .annotation(position: .top, spacing: 2) {
                            if isHovered {
                                Text("\(day.scrollEvents)")
                                    .font(.system(size: 8).bold())
                                    .foregroundStyle(.green)
                            }
                        }

                    if isHovered {
                        RuleMark(x: .value("Date", d))
                            .foregroundStyle(.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(dash: [4, 4]))
                    }
                }
            }
            .chartForegroundStyleScale([
                "Keystrokes": Color.blue,
                "Clicks": Color.orange,
                "Scrolls": Color.green,
            ])
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let plotFrame = geo[proxy.plotFrame!]
                                let x = location.x - plotFrame.origin.x
                                var closest: String?
                                var closestDist: CGFloat = .infinity
                                for label in dateLabels {
                                    if let pos = proxy.position(forX: label) {
                                        let dist = abs(pos - x)
                                        if dist < closestDist {
                                            closestDist = dist
                                            closest = label
                                        }
                                    }
                                }
                                hoveredDate = closest
                            case .ended:
                                hoveredDate = nil
                            }
                        }
                }
            }
            .frame(height: 120)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.55))
        }
    }

    // MARK: - Talk Time (7 Days)

    private var talkTimeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Talk Time")
                .font(.headline)

            let days = store.recentDays(count: chartRange.dayCount)
            let maxSeconds = max(days.map { $0.talkDurationSeconds }.max() ?? 1, 1)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days) { day in
                    let secs = day.talkDurationSeconds
                    let ratio = CGFloat(secs / maxSeconds)
                    let barHeight = max(ratio * 40, secs > 0 ? 3 : 0)

                    VStack(spacing: 3) {
                        Spacer(minLength: 0)
                        if secs > 0 {
                            Text(shortDuration(secs))
                                .font(.system(size: 8).monospacedDigit())
                                .foregroundStyle(.primary.opacity(0.55))
                        }
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.blue.opacity(0.4))
                            .frame(height: barHeight)
                        Text(shortDate(day.date))
                            .font(.system(size: 8))
                            .foregroundStyle(.primary.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 58)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 12) {
            Button {
                updater.checkForUpdates()
            } label: {
                Text("Updates")
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.55))
            }
            .buttonStyle(.plain)

            Button {
                onOpenSettings?()
            } label: {
                Text("Permissions")
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.55))
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: showQuitAlert) {
                Text("Quit")
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: Date())
    }

    private func shortDate(_ dateString: String) -> String {
        let parts = dateString.split(separator: "-")
        guard parts.count == 3 else { return dateString }
        let months = ["", "Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        let monthIndex = Int(parts[1]) ?? 0
        let day = parts[2]
        guard monthIndex >= 1, monthIndex <= 12 else { return dateString }
        return "\(months[monthIndex]) \(day)"
    }

    private func shortDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        if m > 0 {
            return "\(m)m \(s)s"
        }
        return "\(s)s"
    }

    private func showQuitAlert() {
        let alert = NSAlert()
        alert.messageText = "Quit Mac Input Stats?"
        alert.informativeText = "Tracking will stop until you reopen the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }
}
