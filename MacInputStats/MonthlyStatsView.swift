import SwiftUI

struct MonthlyStatsView: View {
    @ObservedObject var store: StatsStore
    @ObservedObject var claudeStore: ClaudeSessionStore
    @ObservedObject var cursorStore: CursorSessionStore
    @ObservedObject var codexStore: CodexSessionStore
    var onClose: (() -> Void)?

    private var inputDays: [DailyStats] { store.recentDays(count: 30) }
    private var totalKeystrokes: Int { inputDays.reduce(0) { $0 + $1.keystrokes } }
    private var totalClicks: Int { inputDays.reduce(0) { $0 + $1.pointerClicks } }
    private var totalScrolls: Int { inputDays.reduce(0) { $0 + $1.scrollEvents } }
    private var totalTalkSeconds: Double { inputDays.reduce(0) { $0 + $1.talkDurationSeconds } }

    private var totalClaudeDuration: Double {
        claudeStore.recentDays(count: 30).reduce(0) { $0 + $1.executionDuration }
    }
    private var totalCursorDuration: Double {
        cursorStore.recentDays(count: 30).reduce(0) { $0 + $1.executionDuration }
    }
    private var totalCodexDuration: Double {
        codexStore.recentDays(count: 30).reduce(0) { $0 + $1.executionDuration }
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
            inputGrid
            if hasAnyAI {
                aiSection
            }
        }
        .padding(16)
        .frame(width: 302)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Spacer()
            VStack(spacing: 2) {
                Text("Last 30 Days")
                    .font(.headline)
                Text(dateRangeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onClose?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var dateRangeLabel: String {
        let days = inputDays
        guard let first = days.first, let last = days.last else { return "" }
        return "\(formatDate(first.date)) - \(formatDate(last.date))"
    }

    // MARK: - Input Stats Grid

    private var inputGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            miniStatCard(title: "Keystrokes", value: formatted(totalKeystrokes), icon: "keyboard")
            miniStatCard(title: "Clicks", value: formatted(totalClicks), icon: "cursorarrow.click.2")
            miniStatCard(title: "Scrolls", value: formatted(totalScrolls), icon: "scroll")
            miniStatCard(title: "Talk Time", value: AppStats.formatDuration(totalTalkSeconds), icon: "waveform")
        }
    }

    private func miniStatCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - AI Section

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Time AI Worked for You")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 4)

            VStack(spacing: 4) {
                if totalClaudeDuration > 0 {
                    aiToolRow(name: "Claude Code", duration: totalClaudeDuration, tint: Self.claudeColor, assetName: "ClaudeCodeIcon", iconSize: 12)
                }
                if totalCursorDuration > 0 {
                    aiToolRow(name: "Cursor", duration: totalCursorDuration, tint: Self.cursorColor, assetName: "CursorIcon", iconSize: 13)
                }
                if totalCodexDuration > 0 {
                    aiToolRow(name: "Codex", duration: totalCodexDuration, tint: Self.codexColor, assetName: "CodexIcon", iconSize: 13)
                }
            }
        }
    }

    private func aiToolRow(name: String, duration: TimeInterval, tint: Color, assetName: String, iconSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .frame(width: iconSize, height: iconSize)
                .frame(width: 22, height: 22)
                .background(tint, in: Circle())

            Text(name)
                .font(.callout)
                .lineLimit(1)

            Spacer()

            Text(AppStats.formatDuration(duration))
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary.opacity(0.55))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
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
