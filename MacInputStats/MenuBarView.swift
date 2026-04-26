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

enum TrendMode: String, CaseIterable {
    case codingTools = "Coding Tools"
    case input = "Input"
}

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
    @ObservedObject var cursorStore: CursorSessionStore
    @ObservedObject var codexStore: CodexSessionStore
    @ObservedObject var projectStore: ProjectStore
    var updater: SPUUpdater
    var onClose: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenMonthlyStats: (() -> Void)?
    @State private var hoveredDate: String?
    @State private var hoveredTalkDate: String?
    @State private var expandedApp: String?
    @AppStorage("statsExpanded") private var statsExpanded = false
    @AppStorage("chartRange") private var chartRange: ChartRange = .sevenDays
    @State private var trendMode: TrendMode = .codingTools
    @State private var selectedDateOffset: Int = 0

    private let panelWidth: CGFloat = 340

    private var isViewingToday: Bool { selectedDateOffset == 0 }

    private var selectedDateKey: String {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: selectedDateOffset, to: Date()) ?? Date()
        return StatsStore.dateKey(for: date)
    }

    private var selectedDayStats: DailyStats {
        store.stats(for: selectedDateKey)
    }

    private var canGoBack: Bool {
        guard let earliest = store.sortedDateKeys.first else { return false }
        return selectedDateKey > earliest
    }

    private var selectedClaudeDuration: TimeInterval {
        claudeStore.duration(for: selectedDateKey)
    }

    private var selectedCursorDuration: TimeInterval {
        cursorStore.duration(for: selectedDateKey)
    }

    private var selectedCodexDuration: TimeInterval {
        codexStore.duration(for: selectedDateKey)
    }

    private var liveTalkTime: String {
        let total = store.today.talkDurationSeconds + micMonitor.ongoingSessionSeconds
        return AppStats.formatDuration(total)
    }

    private var selectedTalkTime: String {
        if isViewingToday {
            return liveTalkTime
        }
        return AppStats.formatDuration(selectedDayStats.talkDurationSeconds)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            todayStats
            if selectedClaudeDuration > 0 || selectedCursorDuration > 0 || selectedCodexDuration > 0
                || (isViewingToday && (!claudeStore.activeSessions.isEmpty || !cursorStore.activeSessions.isEmpty || !codexStore.activeSessions.isEmpty)) {
                Divider().padding(.horizontal, 12)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Time AI Worked for You")
                        .font(.headline)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 2)

                    if selectedClaudeDuration > 0 || (isViewingToday && !claudeStore.activeSessions.isEmpty) {
                        codingToolRow(
                            name: "Claude Code",
                            duration: selectedClaudeDuration,
                            tint: Self.claudeColor,
                            assetName: "ClaudeCodeIcon",
                            iconSize: 14
                        )
                    }
                    if selectedCursorDuration > 0 || (isViewingToday && !cursorStore.activeSessions.isEmpty) {
                        codingToolRow(
                            name: "Cursor",
                            duration: selectedCursorDuration,
                            tint: Self.cursorColor,
                            assetName: "CursorIcon",
                            iconSize: 15
                        )
                    }
                    if selectedCodexDuration > 0 || (isViewingToday && !codexStore.activeSessions.isEmpty) {
                        codingToolRow(
                            name: "Codex",
                            duration: selectedCodexDuration,
                            tint: Self.codexColor,
                            assetName: "CodexIcon",
                            iconSize: 15
                        )
                    }

                    if isViewingToday {
                        aiWeeklyComparison
                    }
                }
                .padding(.vertical, 8)
            }
            Divider().padding(.horizontal, 12)
            topAppsSection
            if projectStore.hasProjects {
                Divider().padding(.horizontal, 12)
                projectStatsSection
            }
            Divider().padding(.horizontal, 12)
            statsDisclosure
            if statsExpanded {
                if trendMode == .codingTools {
                    codingToolsChart
                } else {
                    weeklyChart
                    Divider().padding(.horizontal, 12)
                    talkTimeSection
                }
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
        .animation(.easeInOut(duration: 0.2), value: trendMode)
        .animation(.easeInOut(duration: 0.15), value: selectedDateOffset)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("Activity Bar")
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
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedDateOffset -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary.opacity(canGoBack ? 0.55 : 0.2))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)

                Text(displayDateString)
                    .font(.body)
                    .foregroundStyle(.primary.opacity(0.55))

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedDateOffset += 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary.opacity(isViewingToday ? 0.2 : 0.55))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isViewingToday)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Today Stats

    private var todayStats: some View {
        let day = selectedDayStats
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                statCell(icon: "keyboard", value: "\(day.keystrokes)", label: "Keystrokes")
                statCell(icon: "cursorarrow.click.2", value: "\(day.pointerClicks)", label: "Clicks")
            }
            HStack(spacing: 10) {
                statCell(icon: "scroll", value: "\(day.scrollEvents)", label: "Scrolls")
                statCell(icon: isViewingToday && micMonitor.micInUse ? "mic.fill" : "waveform", value: selectedTalkTime, label: "Talk time")
            }

            if let fact = FunFact.forDay(day) {
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

            let apps = Array(selectedDayStats.topApps.prefix(5))
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

    // MARK: - Projects

    @State private var expandedProject: String?

    private var projectStatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projects")
                .font(.headline)
                .padding(.horizontal, 6)
                .padding(.bottom, 2)

            let day = selectedDayStats
            let activeProjects = projectStore.projects.filter { day.stats(for: $0).screenTimeSeconds > 0 }

            if activeProjects.isEmpty {
                Text("No project activity")
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.55))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
            } else {
                let maxTime = activeProjects.map { day.stats(for: $0).screenTimeSeconds }.max() ?? 1
                ForEach(activeProjects) { project in
                    let stats = day.stats(for: project)
                    projectRow(project: project, stats: stats, maxScreenTime: maxTime)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func projectRow(project: Project, stats: AppStats, maxScreenTime: Double) -> some View {
        let isExpanded = expandedProject == project.name

        return VStack(spacing: 3) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedProject = isExpanded ? nil : project.name
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.55))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)

                    Text(project.name)
                        .font(.body)
                        .lineLimit(1)
                    Spacer()
                    Text(AppStats.formatDuration(stats.screenTimeSeconds))
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
                let day = selectedDayStats
                let projectApps = project.appNames.sorted()
                    .compactMap { name -> (name: String, stats: AppStats)? in
                        guard let s = day.perApp[name], s.screenTimeSeconds > 0 else { return nil }
                        return (name: name, stats: s)
                    }
                    .sorted { $0.stats.screenTimeSeconds > $1.stats.screenTimeSeconds }

                if !projectApps.isEmpty {
                    let maxAppTime = projectApps.first?.stats.screenTimeSeconds ?? 1
                    VStack(spacing: 4) {
                        ForEach(projectApps, id: \.name) { app in
                            projectAppRow(name: app.name, stats: app.stats, maxScreenTime: maxAppTime)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.leading, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    private func projectAppRow(name: String, stats: AppStats, maxScreenTime: Double) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text(AppStats.formatDuration(stats.screenTimeSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.55))
            }

            GeometryReader { geo in
                let ratio = CGFloat(stats.screenTimeSeconds) / CGFloat(Swift.max(maxScreenTime, 1))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.blue.opacity(0.2))
                    .frame(width: geo.size.width * ratio, height: 2)
            }
            .frame(height: 2)

        }
        .padding(.vertical, 2)
    }

    // MARK: - Claude Code

    private static let claudeColor = Color(red: 0xCB / 255.0, green: 0x64 / 255.0, blue: 0x41 / 255.0)
    private static let cursorColor = Color.black
    private static let codexColor = Color(red: 0x10 / 255.0, green: 0xA3 / 255.0, blue: 0x7F / 255.0)

    private var claudeSection: some View {
        codingToolRow(
            name: "Claude Code",
            duration: claudeStore.totalDuration,
            tint: Self.claudeColor,
            assetName: "ClaudeCodeIcon",
            iconSize: 14
        )
    }

    private var cursorSection: some View {
        codingToolRow(
            name: "Cursor",
            duration: cursorStore.totalDuration,
            tint: Self.cursorColor,
            assetName: "CursorIcon",
            iconSize: 15
        )
    }

    private var codexSection: some View {
        codingToolRow(
            name: "Codex",
            duration: codexStore.totalDuration,
            tint: Self.codexColor,
            assetName: "CodexIcon",
            iconSize: 15
        )
    }

    private func codingToolRow(name: String, duration: TimeInterval, tint: Color, assetName: String, iconSize: CGFloat) -> some View {
        HStack(spacing: 8) {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .frame(width: iconSize, height: iconSize)
                .frame(width: 26, height: 26)
                .background(tint, in: Circle())

            Text(name)
                .font(.body)
                .lineLimit(1)

            Spacer()

            Text(AppStats.formatDuration(duration))
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary.opacity(0.55))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var aiDailyAvgLastWeek: TimeInterval {
        let today = StatsStore.dateKey(for: Date())
        let claudeDays = claudeStore.recentDays(count: 8).filter { $0.date != today }
        let cursorDays = cursorStore.recentDays(count: 8).filter { $0.date != today }
        let codexDays = codexStore.recentDays(count: 8).filter { $0.date != today }

        var totalsByDate: [String: TimeInterval] = [:]
        for day in claudeDays { totalsByDate[day.date, default: 0] += day.executionDuration }
        for day in cursorDays { totalsByDate[day.date, default: 0] += day.executionDuration }
        for day in codexDays { totalsByDate[day.date, default: 0] += day.executionDuration }

        let daysWithData = totalsByDate.values.filter { $0 > 0 }
        guard !daysWithData.isEmpty else { return 0 }
        return daysWithData.reduce(0, +) / Double(daysWithData.count)
    }

    private var aiTodayTotal: TimeInterval {
        claudeStore.totalDuration + cursorStore.totalDuration + codexStore.totalDuration
    }

    @ViewBuilder
    private var aiWeeklyComparison: some View {
        let avg = aiDailyAvgLastWeek
        if avg > 0 {
            let today = aiTodayTotal
            let ratio = today / avg
            let aboveAvg = ratio >= 1.0
            let pct = Int(((ratio - 1.0) * 100).rounded())

            HStack(spacing: 6) {
                Image(systemName: aboveAvg ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(aboveAvg ? .green : .primary.opacity(0.45))

                if pct == 0 {
                    Text("On par with your daily avg (\(shortDuration(avg)))")
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.55))
                } else {
                    Text("\(abs(pct))% \(aboveAvg ? "above" : "below") your daily avg (\(shortDuration(avg)))")
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.55))
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 4)
        }
    }

    private func claudeProjectRow(name: String, stats: ClaudeProjectStats, maxDuration: TimeInterval) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                Text(AppStats.formatDuration(stats.executionDuration))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.55))
            }

            GeometryReader { geo in
                let ratio = CGFloat(stats.executionDuration) / CGFloat(Swift.max(maxDuration, 1))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Self.claudeColor.opacity(0.3))
                    .frame(width: geo.size.width * ratio, height: 3)
            }
            .frame(height: 3)

            HStack(spacing: 16) {
                appDetailItem(icon: "hammer", value: "\(stats.toolCallCount)")
                appDetailItem(icon: "text.bubble", value: "\(stats.wordCount)")
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    // MARK: - Stats Disclosure

    private var statsDisclosure: some View {
        HStack {
            Button {
                statsExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text("Trends")
                        .font(.headline)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.55))
                        .rotationEffect(.degrees(statsExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if statsExpanded {
                Spacer()
                ForEach(TrendMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            trendMode = mode
                            hoveredDate = nil
                        }
                    } label: {
                        Text(mode.rawValue)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary.opacity(trendMode == mode ? 1 : 0.35))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Coding Tools Chart

    private var codingToolsChart: some View {
        let claudeDays = claudeStore.recentDays(count: chartRange.dayCount)
        let cursorDays = cursorStore.recentDays(count: chartRange.dayCount)
        let codexDays = codexStore.recentDays(count: chartRange.dayCount)

        // Merge Claude + Cursor + Codex data by date
        var mergedByDate: [String: (claude: DailyClaudeStats?, cursor: DailyClaudeStats?, codex: DailyClaudeStats?)] = [:]
        for day in claudeDays { mergedByDate[day.date, default: (nil, nil, nil)].claude = day }
        for day in cursorDays { mergedByDate[day.date, default: (nil, nil, nil)].cursor = day }
        for day in codexDays { mergedByDate[day.date, default: (nil, nil, nil)].codex = day }

        let allDates = mergedByDate.keys.sorted()
        let compactMode = chartRange.dayCount > 7
        let dateLabels = allDates.map { chartLabel($0) }

        let hasClaude = mergedByDate.values.contains { ($0.claude?.executionDuration ?? 0) > 0 }
        let hasCursor = mergedByDate.values.contains { ($0.cursor?.executionDuration ?? 0) > 0 }
        let hasCodex = mergedByDate.values.contains { ($0.codex?.executionDuration ?? 0) > 0 }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                rangePickerBar
                Spacer()
                if hasClaude { legendDot(color: Self.claudeColor, label: "Claude") }
                if hasCursor { legendDot(color: .purple, label: "Cursor") }
                if hasCodex { legendDot(color: Self.codexColor, label: "Codex") }
            }
            .padding(.horizontal, 6)

            Chart {
                ForEach(allDates, id: \.self) { date in
                    let d = chartLabel(date)
                    let isHovered = hoveredDate == d
                    let entry = mergedByDate[date]!
                    let claudeMins = (entry.claude?.executionDuration ?? 0) / 60
                    let cursorMins = (entry.cursor?.executionDuration ?? 0) / 60
                    let codexMins = (entry.codex?.executionDuration ?? 0) / 60

                    if hasClaude {
                        LineMark(x: .value("Date", d), y: .value("Minutes", claudeMins), series: .value("Tool", "Claude"))
                            .foregroundStyle(by: .value("Tool", "Claude"))
                            .interpolationMethod(.catmullRom)
                    }

                    if hasCursor {
                        LineMark(x: .value("Date", d), y: .value("Minutes", cursorMins), series: .value("Tool", "Cursor"))
                            .foregroundStyle(by: .value("Tool", "Cursor"))
                            .interpolationMethod(.catmullRom)
                    }

                    if hasCodex {
                        LineMark(x: .value("Date", d), y: .value("Minutes", codexMins), series: .value("Tool", "Codex"))
                            .foregroundStyle(by: .value("Tool", "Codex"))
                            .interpolationMethod(.catmullRom)
                    }

                    if isHovered {
                        RuleMark(x: .value("Date", d))
                            .foregroundStyle(.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(dash: [4, 4]))
                            .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                VStack(spacing: 2) {
                                    Text(shortDate(date))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.primary.opacity(0.55))
                                    HStack(spacing: 6) {
                                        if hasClaude {
                                            Text(shortDuration(entry.claude?.executionDuration ?? 0))
                                                .foregroundStyle(Self.claudeColor)
                                        }
                                        if hasCursor {
                                            Text(shortDuration(entry.cursor?.executionDuration ?? 0))
                                                .foregroundStyle(.purple)
                                        }
                                        if hasCodex {
                                            Text(shortDuration(entry.codex?.executionDuration ?? 0))
                                                .foregroundStyle(Self.codexColor)
                                        }
                                    }
                                    .font(.system(size: 10).bold().monospacedDigit())
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                                .offset(y: 30)
                            }

                        if hasClaude {
                            PointMark(x: .value("Date", d), y: .value("Minutes", claudeMins))
                                .foregroundStyle(Self.claudeColor)
                                .symbolSize(30)
                        }
                        if hasCursor {
                            PointMark(x: .value("Date", d), y: .value("Minutes", cursorMins))
                                .foregroundStyle(.purple)
                                .symbolSize(30)
                        }
                        if hasCodex {
                            PointMark(x: .value("Date", d), y: .value("Minutes", codexMins))
                                .foregroundStyle(Self.codexColor)
                                .symbolSize(30)
                        }
                    } else if !compactMode {
                        if hasClaude {
                            PointMark(x: .value("Date", d), y: .value("Minutes", claudeMins))
                                .foregroundStyle(Self.claudeColor)
                                .symbolSize(12)
                        }
                        if hasCursor {
                            PointMark(x: .value("Date", d), y: .value("Minutes", cursorMins))
                                .foregroundStyle(.purple)
                                .symbolSize(12)
                        }
                        if hasCodex {
                            PointMark(x: .value("Date", d), y: .value("Minutes", codexMins))
                                .foregroundStyle(Self.codexColor)
                                .symbolSize(12)
                        }
                    }
                }
            }
            .chartForegroundStyleScale([
                "Claude": Self.claudeColor,
                "Cursor": Color.purple,
                "Codex": Self.codexColor,
            ])
            .chartLegend(.hidden)
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
                        .padding(.horizontal, 7)
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
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button {
                onOpenMonthlyStats?()
            } label: {
                Text("All Time")
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

    private var displayDateString: String {
        if isViewingToday {
            return "Today"
        }
        if selectedDateOffset == -1 {
            return "Yesterday"
        }
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: selectedDateOffset, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
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
        alert.messageText = "Quit Activity Bar?"
        alert.informativeText = "Tracking will stop until you reopen the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }
}
