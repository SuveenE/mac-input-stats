import Foundation

struct AppStats: Codable, Equatable {
    var keystrokes: Int = 0
    var pointerClicks: Int = 0
    var scrollEvents: Int = 0
    var talkDurationSeconds: Double = 0
    var screenTimeSeconds: Double = 0

    var formattedTalkTime: String {
        Self.formatDuration(talkDurationSeconds)
    }

    var formattedScreenTime: String {
        Self.formatDuration(screenTimeSeconds)
    }

    var totalInputs: Int {
        keystrokes + pointerClicks + scrollEvents
    }

    static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }
}

struct DailyStats: Codable, Identifiable, Equatable {
    let date: String
    var keystrokes: Int = 0
    var pointerClicks: Int = 0
    var scrollEvents: Int = 0
    var talkDurationSeconds: Double = 0
    var perApp: [String: AppStats] = [:]

    var id: String { date }

    var formattedTalkTime: String {
        AppStats.formatDuration(talkDurationSeconds)
    }

    private static let hiddenApps: Set<String> = ["loginwindow"]

    /// Top apps sorted by screen time, descending.
    var topApps: [(name: String, stats: AppStats)] {
        perApp
            .filter { !Self.hiddenApps.contains($0.key) }
            .map { (name: $0.key, stats: $0.value) }
            .sorted { $0.stats.screenTimeSeconds > $1.stats.screenTimeSeconds }
    }

    func stats(for project: Project) -> AppStats {
        var combined = AppStats()
        for appName in project.appNames {
            if let s = perApp[appName] {
                combined.keystrokes += s.keystrokes
                combined.pointerClicks += s.pointerClicks
                combined.scrollEvents += s.scrollEvents
                combined.talkDurationSeconds += s.talkDurationSeconds
                combined.screenTimeSeconds += s.screenTimeSeconds
            }
        }
        return combined
    }
}

struct Project: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var appNames: Set<String>

    init(name: String, appNames: Set<String> = []) {
        self.id = UUID()
        self.name = name
        self.appNames = appNames
    }
}
