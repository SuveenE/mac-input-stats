import SwiftUI
import UniformTypeIdentifiers

enum StatsRange: String, CaseIterable {
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case ninetyDays = "90d"
    case allTime = "All"

    var dayCount: Int {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .ninetyDays: return 90
        case .allTime: return 9999
        }
    }

    var label: String { rawValue }
}

struct MonthlyStatsView: View {
    @ObservedObject var store: StatsStore
    @ObservedObject var claudeStore: ClaudeSessionStore
    @ObservedObject var cursorStore: CursorSessionStore
    @ObservedObject var codexStore: CodexSessionStore
    @ObservedObject var categoryStore: CategoryStore
    var onClose: (() -> Void)?

    @State private var selectedRange: StatsRange = .allTime

    private var inputDays: [DailyStats] { store.recentDays(count: selectedRange.dayCount) }
    private var totalKeystrokes: Int { inputDays.reduce(0) { $0 + $1.keystrokes } }
    private var totalClicks: Int { inputDays.reduce(0) { $0 + $1.pointerClicks } }
    private var totalScrolls: Int { inputDays.reduce(0) { $0 + $1.scrollEvents } }
    private var totalTalkSeconds: Double { inputDays.reduce(0) { $0 + $1.talkDurationSeconds } }

    private var totalClaudeDuration: Double {
        claudeStore.recentDays(count: selectedRange.dayCount).reduce(0) { $0 + $1.executionDuration }
    }
    private var totalCursorDuration: Double {
        cursorStore.recentDays(count: selectedRange.dayCount).reduce(0) { $0 + $1.executionDuration }
    }
    private var totalCodexDuration: Double {
        codexStore.recentDays(count: selectedRange.dayCount).reduce(0) { $0 + $1.executionDuration }
    }

    private var hasAnyAI: Bool {
        totalClaudeDuration > 0 || totalCursorDuration > 0 || totalCodexDuration > 0
    }

    private static let claudeColor = Color(red: 0xCB / 255.0, green: 0x64 / 255.0, blue: 0x41 / 255.0)
    private static let cursorColor = Color.black
    private static let codexColor = Color(red: 0x10 / 255.0, green: 0xA3 / 255.0, blue: 0x7F / 255.0)

    var body: some View {
        VStack(spacing: 16) {
            header
            rangePicker
            inputGrid
            if categoryStore.hasCategories {
                categorySection
            }
            if hasAnyAI {
                aiSection
            }
        }
        .padding(16)
        .frame(width: 302)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.black.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .animation(.easeInOut(duration: 0.2), value: selectedRange)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                onClose?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.6))
                    .frame(width: 22, height: 22)
                    .background(.primary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            VStack(spacing: 2) {
                Text("All Time Stats")
                    .font(.headline)
                Text(dateRangeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Export as JSON") { exportJSON() }
                Button("Export as CSV") { exportCSV() }
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.6))
                    .frame(width: 22, height: 22)
                    .background(.primary.opacity(0.12), in: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Download data")
        }
    }

    private var dateRangeLabel: String {
        let days = inputDays
        guard let first = days.first, let last = days.last else { return "" }
        return "\(formatDate(first.date)) - \(formatDate(last.date))"
    }

    // MARK: - Range Picker

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(StatsRange.allCases, id: \.self) { range in
                Button {
                    selectedRange = range
                } label: {
                    Text(range.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selectedRange == range ? .white : .primary.opacity(0.55))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            selectedRange == range ? Color.blue : Color.primary.opacity(0.06),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Input Stats Grid

    private var inputGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            statCell(icon: "keyboard", value: formatted(totalKeystrokes), label: "Keystrokes")
            statCell(icon: "cursorarrow.click.2", value: formatted(totalClicks), label: "Clicks")
            statCell(icon: "scroll", value: formatted(totalScrolls), label: "Scrolls")
            statCell(icon: "waveform", value: AppStats.formatDuration(totalTalkSeconds), label: "Talk Time")
        }
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

    // MARK: - Categories Section

    private func aggregatedCategoryStats(for category: AppCategory) -> AppStats {
        var combined = AppStats()
        for day in inputDays {
            let s = day.stats(for: category)
            combined.keystrokes += s.keystrokes
            combined.pointerClicks += s.pointerClicks
            combined.scrollEvents += s.scrollEvents
            combined.talkDurationSeconds += s.talkDurationSeconds
            combined.screenTimeSeconds += s.screenTimeSeconds
        }
        return combined
    }

    private var categorySection: some View {
        let activeCategories = categoryStore.categories.filter { aggregatedCategoryStats(for: $0).screenTimeSeconds > 0 }

        return Group {
            if !activeCategories.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Divider().padding(.horizontal, 0)
                    Text("Categories")
                        .font(.headline)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 2)

                    VStack(spacing: 4) {
                        ForEach(activeCategories) { category in
                            let stats = aggregatedCategoryStats(for: category)
                            categoryRow(name: category.name, screenTime: stats.screenTimeSeconds)
                        }
                    }
                }
            }
        }
    }

    private func categoryRow(name: String, screenTime: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(.blue)
                .frame(width: 26, height: 26)

            Text(name)
                .font(.body)
                .lineLimit(1)

            Spacer()

            Text(AppStats.formatDuration(screenTime))
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary.opacity(0.55))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - AI Section

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.horizontal, 0)
            Text("Time AI Worked for You")
                .font(.headline)
                .padding(.horizontal, 6)
                .padding(.bottom, 2)

            VStack(spacing: 4) {
                if totalClaudeDuration > 0 {
                    aiToolRow(name: "Claude Code", duration: totalClaudeDuration, tint: Self.claudeColor, assetName: "ClaudeCodeIcon", iconSize: 14)
                }
                if totalCursorDuration > 0 {
                    aiToolRow(name: "Cursor", duration: totalCursorDuration, tint: Self.cursorColor, assetName: "CursorIcon", iconSize: 15)
                }
                if totalCodexDuration > 0 {
                    aiToolRow(name: "Codex", duration: totalCodexDuration, tint: Self.codexColor, assetName: "CodexIcon", iconSize: 15)
                }
            }
        }
    }

    private func aiToolRow(name: String, duration: TimeInterval, tint: Color, assetName: String, iconSize: CGFloat) -> some View {
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
    }

    // MARK: - Export

    private func exportJSON() {
        let exportPayload: [String: Any] = [
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "inputStats": encodeToDictArray(store.days.values.sorted { $0.date < $1.date }),
            "claudeCode": encodeToDictArray(claudeStore.days.values.sorted { $0.date < $1.date }),
            "cursor": encodeToDictArray(cursorStore.days.values.sorted { $0.date < $1.date }),
            "codex": encodeToDictArray(codexStore.days.values.sorted { $0.date < $1.date })
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: exportPayload, options: [.prettyPrinted, .sortedKeys]) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "activity-bar-export.json"
        panel.title = "Export Activity Bar Data"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? jsonData.write(to: url)
    }

    private func exportCSV() {
        var dateSet = Set(store.days.keys)
        dateSet.formUnion(claudeStore.days.keys)
        dateSet.formUnion(cursorStore.days.keys)
        dateSet.formUnion(codexStore.days.keys)
        let allDates = dateSet.sorted()

        var rows: [[String]] = []
        rows.append([
            "date",
            "keystrokes", "clicks", "scrolls", "talk_time_seconds",
            "claude_code_seconds", "cursor_seconds", "codex_seconds"
        ])

        for date in allDates {
            let input = store.days[date]
            let claude = claudeStore.days[date]
            let cursor = cursorStore.days[date]
            let codex = codexStore.days[date]

            rows.append([
                date,
                "\(input?.keystrokes ?? 0)",
                "\(input?.pointerClicks ?? 0)",
                "\(input?.scrollEvents ?? 0)",
                String(format: "%.1f", input?.talkDurationSeconds ?? 0),
                String(format: "%.1f", claude?.executionDuration ?? 0),
                String(format: "%.1f", cursor?.executionDuration ?? 0),
                String(format: "%.1f", codex?.executionDuration ?? 0)
            ])
        }

        let csvString = rows.map { $0.joined(separator: ",") }.joined(separator: "\n")

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "activity-bar-export.csv"
        panel.title = "Export Activity Bar Data"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? csvString.write(to: url, atomically: true, encoding: .utf8)
    }

    private func encodeToDictArray<T: Encodable>(_ items: [T]) -> [[String: Any]] {
        let encoder = JSONEncoder()
        return items.compactMap { item in
            guard let data = try? encoder.encode(item),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return dict
        }
    }

    // MARK: - Helpers

    private func formatted(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formatDate(_ dateString: String) -> String {
        let parts = dateString.split(separator: "-")
        guard parts.count == 3 else { return dateString }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let monthIndex = Int(parts[1]) ?? 0
        let day = parts[2]
        guard monthIndex >= 1, monthIndex <= 12 else { return dateString }
        return "\(months[monthIndex]) \(day)"
    }
}
