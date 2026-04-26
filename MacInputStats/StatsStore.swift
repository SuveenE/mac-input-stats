import Foundation
import SwiftUI

@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var days: [String: DailyStats] = [:]
    @Published private(set) var currentDateKey: String = StatsStore.dateKey(for: Date())

    #if DEBUG
    private let userDefaultsKey = "InputStats.days.v4.dev"
    #else
    private let userDefaultsKey = "InputStats.days.v4"
    #endif

    init() {
        load()
        rolloverIfNeeded()
    }

    static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func rolloverIfNeeded(now: Date = Date()) {
        let today = Self.dateKey(for: now)
        if currentDateKey != today {
            currentDateKey = today
        }
        if days[today] == nil {
            days[today] = DailyStats(date: today)
            save()
        }
    }

    var today: DailyStats {
        days[currentDateKey] ?? DailyStats(date: currentDateKey)
    }

    func stats(for dateKey: String) -> DailyStats {
        days[dateKey] ?? DailyStats(date: dateKey)
    }

    var sortedDateKeys: [String] {
        days.keys.sorted()
    }

    var allAppNames: Set<String> {
        var names = days.values.reduce(into: Set<String>()) { result, day in
            result.formUnion(day.perApp.keys)
        }
        names.remove("")
        return names
    }

    var recentDays: [DailyStats] {
        recentDays(count: 7)
    }

    func recentDays(count: Int) -> [DailyStats] {
        days.values
            .sorted { $0.date > $1.date }
            .prefix(count)
            .reversed()
            .map { $0 }
    }

    // MARK: - Increment Methods

    func incrementKeystroke(app: String) {
        rolloverIfNeeded()
        days[currentDateKey, default: DailyStats(date: currentDateKey)].keystrokes += 1
        days[currentDateKey]?.perApp[app, default: AppStats()].keystrokes += 1
        save()
    }

    func incrementPointerClick(app: String) {
        rolloverIfNeeded()
        days[currentDateKey, default: DailyStats(date: currentDateKey)].pointerClicks += 1
        days[currentDateKey]?.perApp[app, default: AppStats()].pointerClicks += 1
        save()
    }

    func incrementScroll(app: String) {
        rolloverIfNeeded()
        days[currentDateKey, default: DailyStats(date: currentDateKey)].scrollEvents += 1
        days[currentDateKey]?.perApp[app, default: AppStats()].scrollEvents += 1
        save()
    }

    func addTalkDuration(_ seconds: Double, app: String) {
        rolloverIfNeeded()
        days[currentDateKey, default: DailyStats(date: currentDateKey)].talkDurationSeconds += seconds
        days[currentDateKey]?.perApp[app, default: AppStats()].talkDurationSeconds += seconds
        save()
    }

    func addScreenTime(_ seconds: Double, app: String) {
        rolloverIfNeeded()
        days[currentDateKey]?.perApp[app, default: AppStats()].screenTimeSeconds += seconds
        save()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(days) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: DailyStats].self, from: data) else {
            return
        }
        days = decoded
    }

    func resetToday() {
        days[currentDateKey] = DailyStats(date: currentDateKey)
        save()
    }
}
