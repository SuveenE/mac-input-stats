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

// MARK: - Fun Facts

private enum FunFact {
    static let secondsPerClick = 0.50
    static let keysPerPage = 550
    static let pixelsPerScroll = 250
    static let screenHeight = 1080

    /// Returns a fun fact string for the given stats, deterministically chosen per date.
    static func forDay(_ stats: DailyStats) -> String? {
        var facts: [String] = []

        if stats.keystrokes > 0 {
            let pages = Double(stats.keystrokes) / Double(keysPerPage)
            if pages >= 1 {
                let formatted = NumberFormatter.localizedString(from: NSNumber(value: stats.keystrokes), number: .decimal)
                let fullPages = Int(pages.rounded())
                facts.append("✍️ You typed \(formatted) keys today. That's about writing \(fullPages) full page\(fullPages == 1 ? "" : "s").")
            }
        }

        if stats.pointerClicks > 0 {
            let clickMins = (Double(stats.pointerClicks) * secondsPerClick) / 60
            if clickMins >= 1 {
                let formatted = NumberFormatter.localizedString(from: NSNumber(value: stats.pointerClicks), number: .decimal)
                facts.append("🥁 You clicked \(formatted) times. That's like tapping your desk for about \(Int(clickMins.rounded())) minute\(Int(clickMins.rounded()) == 1 ? "" : "s").")
            }
        }

        // TODO: bring back scroll fun fact later
        // if stats.scrollEvents > 0 {
        //     let screenfuls = (stats.scrollEvents * pixelsPerScroll) / screenHeight
        //     if screenfuls >= 1 {
        //         facts.append("📜 You moved through about \(screenfuls) screenful\(screenfuls == 1 ? "" : "s") of content today.")
        //     }
        // }

        guard !facts.isEmpty else { return nil }
        // Deterministic pick based on date string so it stays stable within the day
        // (Swift's hashValue is randomized per launch, so use a simple djb2 hash)
        let hash = stats.date.utf8.reduce(5381) { (($0 << 5) &+ $0) &+ Int($1) }
        let index = abs(hash) % facts.count
        return facts[index]
    }
}

// MARK: - Main View

struct MenuBarView: View {
    @ObservedObject var store: StatsStore
    @ObservedObject var micMonitor: SpeechDetector
    @ObservedObject var claudeStore: ClaudeSessionStore
    var updater: SPUUpdater
    var onClose: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    @State private var hoveredDate: String?
    @State private var hoveredTalkDate: String?
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
            if !claudeStore.activeSessions.isEmpty {
                Divider().padding(.horizontal, 12)
                claudeSection
            }
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
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                statCell(icon: "keyboard", value: "\(store.today.keystrokes)", label: "Keystrokes")
                statCell(icon: "cursorarrow.click.2", value: "\(store.today.pointerClicks)", label: "Clicks")
            }
            HStack(spacing: 10) {
                statCell(icon: "scroll", value: "\(store.today.scrollEvents)", label: "Scrolls")
                statCell(icon: micMonitor.micInUse ? "mic.fill" : "waveform", value: liveTalkTime, label: "Talk time")
            }

            if let fact = FunFact.forDay(store.today) {
                Text(fact)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func statCell(icon: String, value: String, label: String, tint: Color = .blue) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(tint, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.primary.opacity(0.5))
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statRow(icon: String, value: String, label: String, tint: Color = .blue) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(tint, in: Circle())

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

    // MARK: - Claude Code

    private static let claudeColor = Color(red: 0xCB / 255.0, green: 0x64 / 255.0, blue: 0x41 / 255.0)

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Code")
                .font(.headline)
                .padding(.horizontal, 6)
                .padding(.bottom, 2)

            VStack(spacing: 2) {
                statRow(icon: "clock",
                        value: AppStats.formatDuration(claudeStore.totalDuration),
                        label: "Duration today",
                        tint: Self.claudeColor)
                statRow(icon: "text.bubble",
                        value: formatWordCount(claudeStore.totalWords),
                        label: "Words to Claude",
                        tint: Self.claudeColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
        let compactMode = chartRange.dayCount > 7
        let dateLabels = days.map { chartLabel($0.date) }

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
                    let d = chartLabel(day.date)
                    let isHovered = hoveredDate == d

                    LineMark(x: .value("Date", d), y: .value("Count", day.keystrokes), series: .value("Metric", "Keystrokes"))
                        .foregroundStyle(by: .value("Metric", "Keystrokes"))
                        .interpolationMethod(.catmullRom)

                    LineMark(x: .value("Date", d), y: .value("Count", day.pointerClicks), series: .value("Metric", "Clicks"))
                        .foregroundStyle(by: .value("Metric", "Clicks"))
                        .interpolationMethod(.catmullRom)

                    LineMark(x: .value("Date", d), y: .value("Count", day.scrollEvents), series: .value("Metric", "Scrolls"))
                        .foregroundStyle(by: .value("Metric", "Scrolls"))
                        .interpolationMethod(.catmullRom)

                    if isHovered {
                        RuleMark(x: .value("Date", d))
                            .foregroundStyle(.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(dash: [4, 4]))
                            .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                VStack(spacing: 2) {
                                    Text(shortDate(day.date))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.primary.opacity(0.55))
                                    HStack(spacing: 6) {
                                        Text("\(day.keystrokes)").foregroundStyle(.blue)
                                        Text("\(day.pointerClicks)").foregroundStyle(.orange)
                                        Text("\(day.scrollEvents)").foregroundStyle(.green)
                                    }
                                    .font(.system(size: 10).bold().monospacedDigit())
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                                .offset(y: 30)
                            }

                        PointMark(x: .value("Date", d), y: .value("Count", day.keystrokes))
                            .foregroundStyle(.blue)
                            .symbolSize(30)
                        PointMark(x: .value("Date", d), y: .value("Count", day.pointerClicks))
                            .foregroundStyle(.orange)
                            .symbolSize(30)
                        PointMark(x: .value("Date", d), y: .value("Count", day.scrollEvents))
                            .foregroundStyle(.green)
                            .symbolSize(30)
                    } else if !compactMode {
                        PointMark(x: .value("Date", d), y: .value("Count", day.keystrokes))
                            .foregroundStyle(.blue)
                            .symbolSize(12)
                        PointMark(x: .value("Date", d), y: .value("Count", day.pointerClicks))
                            .foregroundStyle(.orange)
                            .symbolSize(12)
                        PointMark(x: .value("Date", d), y: .value("Count", day.scrollEvents))
                            .foregroundStyle(.green)
                            .symbolSize(12)
                    }
                }
            }
            .chartForegroundStyleScale([
                "Keystrokes": Color.blue,
                "Clicks": Color.orange,
                "Scrolls": Color.green,
            ])
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine()
                    if compactMode {
                        AxisValueLabel() {
                            if let label = value.as(String.self) {
                                if shouldShowXLabel(label, in: dateLabels) {
                                    Text(label)
                                        .font(.system(size: 9))
                                }
                            }
                        }
                    } else {
                        AxisValueLabel()
                            .font(.system(size: 9))
                    }
                }
            }
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

    // MARK: - Talk Time

    private var talkTimeSection: some View {
        let days = store.recentDays(count: chartRange.dayCount)
        let compactMode = chartRange.dayCount > 7
        let labels = days.map { chartLabel($0.date) }

        return VStack(alignment: .leading, spacing: 6) {
            Text("Talk Time")
                .font(.headline)

            Chart {
                ForEach(days) { day in
                    let d = chartLabel(day.date)
                    let isHovered = hoveredTalkDate == d
                    BarMark(
                        x: .value("Date", d),
                        y: .value("Duration", day.talkDurationSeconds / 60)
                    )
                    .foregroundStyle(isHovered ? .blue.opacity(0.7) : .blue.opacity(0.4))
                    .cornerRadius(2)
                    .annotation(position: .top, spacing: 2) {
                        if isHovered, day.talkDurationSeconds > 0 {
                            Text(shortDuration(day.talkDurationSeconds))
                                .font(.system(size: 9).bold().monospacedDigit())
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
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
                                for label in labels {
                                    if let pos = proxy.position(forX: label) {
                                        let dist = abs(pos - x)
                                        if dist < closestDist {
                                            closestDist = dist
                                            closest = label
                                        }
                                    }
                                }
                                hoveredTalkDate = closest
                            case .ended:
                                hoveredTalkDate = nil
                            }
                        }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let mins = value.as(Double.self) {
                            Text(talkAxisLabel(mins))
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            if !compactMode || shouldShowXLabel(label, in: labels) {
                                Text(label)
                                    .font(.system(size: 9))
                            }
                        }
                    }
                }
            }
            .frame(height: 60)
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

    /// Compact label for chart x-axis: "Apr 2" for <=7 days, "2" for longer ranges
    private func chartLabel(_ dateString: String) -> String {
        if chartRange.dayCount <= 7 {
            return shortDate(dateString)
        }
        let parts = dateString.split(separator: "-")
        guard parts.count == 3 else { return dateString }
        let day = Int(parts[2]) ?? 0
        let months = ["", "Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        let monthIndex = Int(parts[1]) ?? 0
        // Show "Mon D" on 1st of month, otherwise just day number
        if day == 1, monthIndex >= 1, monthIndex <= 12 {
            return "\(months[monthIndex]) 1"
        }
        return "\(day)"
    }

    /// Only show every Nth x-axis label to avoid crowding
    private func shouldShowXLabel(_ label: String, in allLabels: [String]) -> Bool {
        guard let idx = allLabels.firstIndex(of: label) else { return false }
        let step = chartRange.dayCount <= 14 ? 2 : 5
        return idx % step == 0 || idx == allLabels.count - 1
    }

    private func talkAxisLabel(_ minutes: Double) -> String {
        if minutes >= 60 {
            return "\(Int(minutes / 60))h"
        }
        return "\(Int(minutes))m"
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

    private func formatWordCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
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
