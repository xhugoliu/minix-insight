import MinixInsightCore
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            stats
            Divider()
            trend
            Divider()
            KeyboardLayoutView()
            Divider()
            actions
            if let detail = footerMessage {
                Divider()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(appState.statusShowsIssue ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 560, height: 410, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text("Minix Insight")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let detail = appState.statusDetail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(appState.statusShowsIssue ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
    }

    private var stats: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Today")
                    .foregroundStyle(.secondary)
                Text("\(appState.todayPresses) presses")
            }
            GridRow {
                Text("Today Held")
                    .foregroundStyle(.secondary)
                Text(formatDuration(appState.todayHeldMs))
            }
            GridRow {
                Text("7 Days")
                    .foregroundStyle(.secondary)
                Text("\(appState.last7DaysPresses) presses")
            }
            GridRow {
                Text("7 Days Held")
                    .foregroundStyle(.secondary)
                Text(formatDuration(appState.last7DaysHeldMs))
            }
            GridRow {
                Text("Last")
                    .foregroundStyle(.secondary)
                Text(appState.lastEventText)
                    .lineLimit(1)
            }
        }
        .font(.system(.body, design: .rounded))
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("7-Day Trend")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(appState.dailySummaries, id: \.dayStart) { summary in
                    DailyTrendBar(
                        label: weekdayLabel(for: summary.dayStart),
                        value: summary.pressCount,
                        maxValue: maxDailyPressCount,
                        heldMs: summary.heldMs
                    )
                }
            }
            .frame(height: 92, alignment: .bottomLeading)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(appState.isLogging ? "Pause Logging" : "Resume Logging") {
                appState.toggleLogging()
            }
            Button("Export Today CSV") {
                appState.exportToday()
            }
            Button("Export 7-Day Summary") {
                appState.exportSummary()
            }
            Button("Reveal Database") {
                appState.revealDatabase()
            }
            Spacer()
            Button("Quit") {
                appState.quit()
            }
        }
        .frame(height: 32)
    }

    private var statusText: String {
        if !appState.isLogging {
            return "Paused"
        }

        switch appState.status {
        case .connected(let name):
            return name
        case .waiting(let reason):
            switch reason {
            case .initial:
                return "Waiting for keyboard"
            case .disconnected:
                return "Keyboard disconnected"
            }
        case .stopped:
            return "Paused"
        case .issue(let issue):
            return issue.title
        }
    }

    private var statusColor: Color {
        if appState.statusShowsIssue {
            return .orange
        }
        return appState.status.isConnected && appState.isLogging ? .green : .yellow
    }

    private var footerMessage: String? {
        guard appState.statusShowsIssue else {
            return nil
        }
        return appState.statusDetail
    }

    private var maxDailyPressCount: Int {
        max(appState.dailySummaries.map(\.pressCount).max() ?? 0, 1)
    }

    private func weekdayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    private func formatDuration(_ milliseconds: Int64) -> String {
        let seconds = Double(milliseconds) / 1000
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        return String(format: "%.1fmin", seconds / 60)
    }
}

private struct DailyTrendBar: View {
    let label: String
    let value: Int
    let maxValue: Int
    let heldMs: Int64

    var body: some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
            RoundedRectangle(cornerRadius: 5)
                .fill(barColor)
                .frame(width: 22, height: barHeight)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text(heldText)
                .font(.system(size: 8, weight: .regular, design: .rounded))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .frame(width: 34, alignment: .bottom)
    }

    private var barHeight: CGFloat {
        let ratio = Double(value) / Double(maxValue)
        return max(12, 12 + ratio * 42)
    }

    private var barColor: Color {
        value == 0 ? Color.secondary.opacity(0.15) : Color.accentColor.opacity(0.22 + min(Double(value) / Double(maxValue), 1) * 0.5)
    }

    private var heldText: String {
        let seconds = Double(heldMs) / 1000
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        return String(format: "%.1fm", seconds / 60)
    }
}
