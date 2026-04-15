import Foundation

/// Tracks active Codex sessions and maps hook events to sprite states.
/// Mirrors ClaudeSessionStore but persists separately.
@MainActor
final class CodexSessionStore: ObservableObject {
    @Published private(set) var sessions: [String: ClaudeSession] = [:]
    @Published private(set) var orderedSessionIds: [String] = []
    @Published private(set) var days: [String: DailyClaudeStats] = [:]

    private let userDefaultsKey = "CodexStats.days.v1"
    private let defaults: UserDefaults

    private static func sharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.suveene.MacInputStats") ?? .standard
    }

    private var currentDateKey: String = StatsStore.dateKey(for: Date())

    init() {
        defaults = Self.sharedDefaults()
        load()
        rolloverIfNeeded()
    }

    private func rolloverIfNeeded() {
        let today = StatsStore.dateKey(for: Date())
        if currentDateKey != today {
            currentDateKey = today
        }
        if days[today] == nil {
            days[today] = DailyClaudeStats(date: today)
            save()
        }
    }

    var activeSessions: [ClaudeSession] {
        orderedSessionIds.compactMap { sessions[$0] }
    }

    var totalToolCalls: Int {
        sessions.values.reduce(0) { $0 + $1.toolCallCount }
    }

    var totalWords: Int {
        days[currentDateKey]?.wordCount ?? 0
    }

    var totalDuration: TimeInterval {
        let persisted = days[currentDateKey]?.executionDuration ?? 0
        let now = Date()
        let inProgress = sessions.values.reduce(0.0) { total, session in
            guard let activeStart = session.activeStartedAt else { return total }
            return total + now.timeIntervalSince(activeStart)
        }
        return persisted + inProgress
    }

    var todayTopProjects: [(name: String, stats: ClaudeProjectStats)] {
        days[currentDateKey]?.topProjects ?? []
    }

    func recentDays(count: Int) -> [DailyClaudeStats] {
        days.values
            .sorted { $0.date > $1.date }
            .prefix(count)
            .reversed()
            .map { $0 }
    }

    var recentActivity: [ActivityItem] {
        sessions.values
            .flatMap { $0.recentEvents }
            .sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Event Handling

    func handleEvent(_ event: ClaudeEvent) {
        let id = event.sessionId
        guard !id.isEmpty else { return }

        rolloverIfNeeded()

        let newState = spriteState(for: event)
        let item = ActivityItem(
            timestamp: Date(),
            event: event.event,
            tool: event.tool,
            status: event.status
        )

        let words = event.event == .userPromptSubmit
            ? Self.countWords(event.userPrompt)
            : 0

        if words > 0 {
            days[currentDateKey, default: DailyClaudeStats(date: currentDateKey)].wordCount += words
        }

        if var session = sessions[id] {
            let wasActive = session.spriteState == .working || session.spriteState == .compacting
            let isActive = newState == .working || newState == .compacting
            if wasActive && !isActive, let start = session.activeStartedAt {
                let chunk = Date().timeIntervalSince(start)
                session.activeDuration += chunk
                session.activeStartedAt = nil
                days[currentDateKey, default: DailyClaudeStats(date: currentDateKey)].executionDuration += chunk
                if let project = Self.projectName(for: session.cwd) {
                    days[currentDateKey]?.perProject[project, default: ClaudeProjectStats()].executionDuration += chunk
                }
            } else if !wasActive && isActive {
                session.activeStartedAt = Date()
            }

            session.spriteState = newState
            session.lastEvent = event.event
            session.lastActivityAt = Date()
            session.eventCount += 1
            session.wordCount += words
            if let tool = event.tool {
                session.lastTool = tool
            }
            if event.event == .preToolUse {
                session.toolCallCount += 1
                if let project = Self.projectName(for: session.cwd) {
                    days[currentDateKey, default: DailyClaudeStats(date: currentDateKey)].perProject[project, default: ClaudeProjectStats()].toolCallCount += 1
                }
            }
            if words > 0, let project = Self.projectName(for: session.cwd) {
                days[currentDateKey]?.perProject[project, default: ClaudeProjectStats()].wordCount += words
            }
            if let cwd = event.cwd, !cwd.isEmpty {
                session.cwd = cwd
            }
            session.appendEvent(item)
            sessions[id] = session
        } else {
            var session = ClaudeSession(id: id)
            session.spriteState = newState
            session.lastEvent = event.event
            session.cwd = event.cwd
            session.interactive = event.interactive ?? true
            session.eventCount = 1
            session.toolCallCount = event.event == .preToolUse ? 1 : 0
            session.wordCount = words
            if newState == .working || newState == .compacting {
                session.activeStartedAt = Date()
            }
            if let tool = event.tool {
                session.lastTool = tool
            }
            let project = Self.projectName(for: session.cwd)
            if event.event == .preToolUse, let project {
                days[currentDateKey, default: DailyClaudeStats(date: currentDateKey)].perProject[project, default: ClaudeProjectStats()].toolCallCount += 1
            }
            if words > 0, let project {
                days[currentDateKey, default: DailyClaudeStats(date: currentDateKey)].perProject[project, default: ClaudeProjectStats()].wordCount += words
            }
            session.appendEvent(item)
            sessions[id] = session
            orderedSessionIds.append(id)
        }

        save()

        if event.event == .sessionEnd {
            if var session = sessions[id], let start = session.activeStartedAt {
                let chunk = Date().timeIntervalSince(start)
                session.activeDuration += chunk
                session.activeStartedAt = nil
                days[currentDateKey, default: DailyClaudeStats(date: currentDateKey)].executionDuration += chunk
                if let project = Self.projectName(for: session.cwd) {
                    days[currentDateKey]?.perProject[project, default: ClaudeProjectStats()].executionDuration += chunk
                }
                sessions[id] = session
                save()
            }
            scheduleSessionCleanup(id: id)
        }
    }

    // MARK: - State Machine

    private func spriteState(for event: ClaudeEvent) -> SpriteState {
        switch event.event {
        case .sessionStart:
            return .idle
        case .userPromptSubmit:
            return .working
        case .preToolUse:
            return .working
        case .postToolUse:
            return .working
        case .preCompact:
            return .compacting
        case .permissionRequest:
            return .needsPermission
        case .stop, .subagentStop:
            return .idle
        case .sessionEnd:
            return .sleeping
        }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(days) {
            defaults.set(data, forKey: userDefaultsKey)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: DailyClaudeStats].self, from: data) else {
            return
        }
        days = decoded
    }

    // MARK: - Helpers

    static func projectName(for cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    private static func countWords(_ text: String?) -> Int {
        guard let text, !text.isEmpty else { return 0 }
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    // MARK: - Session Cleanup

    private func scheduleSessionCleanup(id: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self else { return }
            if self.sessions[id]?.spriteState == .sleeping {
                self.sessions.removeValue(forKey: id)
                self.orderedSessionIds.removeAll { $0 == id }
            }
        }
    }
}
