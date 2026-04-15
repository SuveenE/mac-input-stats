import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var store: StatsStore
    @ObservedObject var micMonitor: SpeechDetector
    @State private var hoveredDate: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                todayGrid
                appBreakdown
                weeklyChart
                talkTimeChart
            }
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Activity Bar")
                    .font(.largeTitle.bold())
                Text(store.currentDateKey)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if micMonitor.micInUse {
                Label("Mic in use", systemImage: "mic.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }
        }
    }

    // MARK: - Today Grid

    private var todayGrid: some View {
        let stats = store.today
        return LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCard(title: "Keystrokes", value: "\(stats.keystrokes)", icon: "keyboard")
            StatCard(title: "Clicks", value: "\(stats.pointerClicks)", icon: "cursorarrow.click.2")
            StatCard(title: "Scrolls", value: "\(stats.scrollEvents)", icon: "scroll")
            StatCard(title: "Talk Time", value: stats.formattedTalkTime, icon: "waveform")
        }
    }

    // MARK: - Per-App Breakdown

    private var appBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today by App")
                .font(.headline)

            let apps = store.today.topApps
            if apps.isEmpty {
                Text("No activity yet")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                // Column headers
                HStack(spacing: 0) {
                    Text("App")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Keys")
                        .frame(width: 60, alignment: .trailing)
                    Text("Clicks")
                        .frame(width: 60, alignment: .trailing)
                    Text("Scrolls")
                        .frame(width: 60, alignment: .trailing)
                    Text("Mic")
                        .frame(width: 70, alignment: .trailing)
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)

                Divider()

                ForEach(apps, id: \.name) { app in
                    HStack(spacing: 0) {
                        Text(app.name)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(app.stats.keystrokes)")
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                        Text("\(app.stats.pointerClicks)")
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                        Text("\(app.stats.scrollEvents)")
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                        Text(app.stats.talkDurationSeconds > 0 ? app.stats.formattedTalkTime : "-")
                            .monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                    }
                    .font(.callout)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Weekly Chart

    private var weeklyChart: some View {
        let days = store.recentDays
        let dateLabels = days.map { shortDate($0.date) }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 Days")
                .font(.headline)

            Chart {
                ForEach(days) { day in
                    let d = shortDate(day.date)
                    let isHovered = hoveredDate == d

                    LineMark(x: .value("Date", d), y: .value("Count", day.keystrokes), series: .value("Metric", "Keystrokes"))
                        .foregroundStyle(by: .value("Metric", "Keystrokes"))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", d), y: .value("Count", day.keystrokes))
                        .foregroundStyle(by: .value("Metric", "Keystrokes"))
                        .symbolSize(isHovered ? 60 : 30)
                        .annotation(position: .top, spacing: 4) {
                            if isHovered {
                                Text("\(day.keystrokes)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.blue)
                            }
                        }

                    LineMark(x: .value("Date", d), y: .value("Count", day.pointerClicks), series: .value("Metric", "Clicks"))
                        .foregroundStyle(by: .value("Metric", "Clicks"))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", d), y: .value("Count", day.pointerClicks))
                        .foregroundStyle(by: .value("Metric", "Clicks"))
                        .symbolSize(isHovered ? 60 : 30)
                        .annotation(position: .top, spacing: 4) {
                            if isHovered {
                                Text("\(day.pointerClicks)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.orange)
                            }
                        }

                    LineMark(x: .value("Date", d), y: .value("Count", day.scrollEvents), series: .value("Metric", "Scrolls"))
                        .foregroundStyle(by: .value("Metric", "Scrolls"))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", d), y: .value("Count", day.scrollEvents))
                        .foregroundStyle(by: .value("Metric", "Scrolls"))
                        .symbolSize(isHovered ? 60 : 30)
                        .annotation(position: .top, spacing: 4) {
                            if isHovered {
                                Text("\(day.scrollEvents)")
                                    .font(.caption2.bold())
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
                                // Find closest date by x position
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
            .frame(height: 220)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Talk Time Chart

    private var talkTimeChart: some View {
        let days = store.recentDays
        let maxSeconds = max(days.map { $0.talkDurationSeconds }.max() ?? 1, 1)
        let barMaxHeight: CGFloat = 120

        return VStack(alignment: .leading, spacing: 8) {
            Text("Talk Time (7 Days)")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days) { day in
                    let secs = day.talkDurationSeconds
                    let ratio = CGFloat(secs / maxSeconds)
                    let barHeight = max(ratio * barMaxHeight, secs > 0 ? 4 : 0)

                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        if secs > 0 {
                            Text(shortDuration(secs))
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.purple)
                            .frame(height: barHeight)
                        Text(shortDate(day.date))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: barMaxHeight + 40)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func shortDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return "\(h)h \(m)m \(s)s"
        }
        return "\(m)m \(s)s"
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
}

// MARK: - StatCard

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.bold().monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
