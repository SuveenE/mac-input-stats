import SwiftUI

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
