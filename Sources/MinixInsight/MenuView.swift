import MinixInsightCore
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var appState: AppState
    @State private var topKeysCardHeight: CGFloat = 0
    @State private var handLoadCardHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summaryCards
            trend
            insights
            KeyboardLayoutView()
            actions
            if let detail = footerMessage {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(appState.statusShowsIssue ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 560, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 9, height: 9)
                    Text("Minix Insight")
                        .font(.headline)
                }
                Text(statusText)
                    .font(.subheadline.weight(.medium))
                if let detail = appState.statusDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(appState.statusShowsIssue ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            statusBadge
        }
        .padding(14)
        .background(sectionBackground)
    }

    private var summaryCards: some View {
        HStack(spacing: 8) {
            MetricCard(title: "Today", value: "\(appState.todayPresses)", detail: "press")
            MetricCard(title: "Held", value: formatDuration(appState.todayHeldMs), detail: "today")
            MetricCard(title: "7D Press", value: "\(appState.last7DaysPresses)", detail: "press")
            MetricCard(title: "7D Held", value: formatDuration(appState.last7DaysHeldMs), detail: "range")
        }
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("7-Day Trend")
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(appState.dailySummaries, id: \.dayStart) { summary in
                    DailyTrendBar(
                        label: dayLabel(for: summary.dayStart),
                        value: summary.pressCount,
                        maxValue: maxDailyPressCount,
                        heldMs: summary.heldMs
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 92, alignment: .bottomLeading)
        }
        .padding(14)
        .background(sectionBackground)
    }

    private var insights: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                topKeysCard
                handLoadCard
            }
            VStack(alignment: .leading, spacing: 10) {
                topKeysCard
                handLoadCard
            }
        }
    }

    private var topKeysCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Top Keys")
            if topKeys.isEmpty {
                Text("No activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(topKeys.enumerated()), id: \.offset) { index, summary in
                    HStack(spacing: 8) {
                        Text("#\(index + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("r\(summary.row)c\(summary.col)")
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text("\(summary.pressCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(
            HeightReader { height in
                topKeysCardHeight = height
            }
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: equalizedInsightCardHeight, alignment: .topLeading)
        .background(sectionBackground)
    }

    private var actions: some View {
        HStack(spacing: 0) {
            actionButton("Pause Logging", alternate: "Resume Logging", isAlternate: !appState.isLogging) {
                appState.toggleLogging()
            }
            Spacer(minLength: 12)
            actionButton("Export Today CSV") {
                appState.exportToday()
            }
            Spacer(minLength: 12)
            actionButton("Export 7-Day Summary") {
                appState.exportSummary()
            }
            Spacer(minLength: 12)
            actionButton("Reveal Database") {
                appState.revealDatabase()
            }
            Spacer(minLength: 12)
            actionButton("Quit") {
                appState.quit()
            }
        }
    }

    private var statusText: String {
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

    private var statusBadge: some View {
        Text(appState.isLogging ? "Live" : "Paused")
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
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

    private var topKeys: [KeySummary] {
        appState.keySummaries
            .filter { $0.pressCount > 0 }
            .sorted {
                if $0.pressCount == $1.pressCount {
                    return $0.heldMs > $1.heldMs
                }
                return $0.pressCount > $1.pressCount
            }
            .prefix(3)
            .map { $0 }
    }

    private var leftPresses: Int {
        presses(in: appState.configuration.presentation.leftRows)
    }

    private var rightPresses: Int {
        presses(in: appState.configuration.presentation.rightRows)
    }

    private var leftHeldMs: Int64 {
        heldMs(in: appState.configuration.presentation.leftRows)
    }

    private var rightHeldMs: Int64 {
        heldMs(in: appState.configuration.presentation.rightRows)
    }

    private var totalPresses: Int {
        max(leftPresses + rightPresses, 1)
    }

    private var maxDailyPressCount: Int {
        max(appState.dailySummaries.map(\.pressCount).max() ?? 0, 1)
    }

    private var equalizedInsightCardHeight: CGFloat? {
        let height = max(topKeysCardHeight, handLoadCardHeight)
        return height > 0 ? height : nil
    }

    private func dayLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    private func presses(in rows: Range<Int>) -> Int {
        appState.keySummaries
            .filter { rows.contains($0.row) }
            .reduce(0) { $0 + $1.pressCount }
    }

    private func heldMs(in rows: Range<Int>) -> Int64 {
        appState.keySummaries
            .filter { rows.contains($0.row) }
            .reduce(0) { $0 + $1.heldMs }
    }

    private func loadFraction(_ value: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(value) / Double(total)
    }

    private var handLoadCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Hand Load")
            UnifiedLoadBar(
                leftLabel: "Left",
                leftPresses: leftPresses,
                leftHeldText: shortDuration(leftHeldMs),
                leftFraction: loadFraction(leftPresses, total: totalPresses),
                rightLabel: "Right",
                rightPresses: rightPresses,
                rightHeldText: shortDuration(rightHeldMs)
            )
        }
        .padding(14)
        .background(
            HeightReader { height in
                handLoadCardHeight = height
            }
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: equalizedInsightCardHeight, alignment: .topLeading)
        .background(sectionBackground)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.secondary.opacity(0.08))
    }

    private func actionButton(_ title: String, alternate: String? = nil, isAlternate: Bool = false, action: @escaping () -> Void) -> some View {
        Button(isAlternate ? (alternate ?? title) : title, action: action)
            .controlSize(.small)
            .lineLimit(1)
    }

    private func formatDuration(_ milliseconds: Int64) -> String {
        let seconds = Double(milliseconds) / 1000
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        return String(format: "%.1fmin", seconds / 60)
    }

    private func shortDuration(_ milliseconds: Int64) -> String {
        let seconds = Double(milliseconds) / 1000
        if seconds < 10 {
            return String(format: "%.1fs", seconds)
        }
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        return String(format: "%.1fm", seconds / 60)
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

private struct HeightReader: View {
    let onChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    onChange(proxy.size.height)
                }
                .onChange(of: proxy.size.height) { _, newValue in
                    onChange(newValue)
                }
        }
    }
}

private struct UnifiedLoadBar: View {
    let leftLabel: String
    let leftPresses: Int
    let leftHeldText: String
    let leftFraction: Double
    let rightLabel: String
    let rightPresses: Int
    let rightHeldText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let leftWidth = max(14, proxy.size.width * leftFraction)
                let rightWidth = max(14, proxy.size.width - leftWidth)
                let overlap: CGFloat = 12
                let leftIsLonger = leftWidth >= rightWidth
                let leftColor = leftIsLonger ? Color.blue.opacity(0.82) : Color.blue.opacity(0.38)
                let rightColor = leftIsLonger ? Color.blue.opacity(0.38) : Color.blue.opacity(0.82)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(leftColor)
                        .frame(width: min(proxy.size.width, leftWidth + overlap))
                    Capsule()
                        .fill(rightColor)
                        .frame(width: min(proxy.size.width, rightWidth + overlap))
                        .offset(x: max(0, leftWidth - overlap))
                }
            }
            .frame(height: 10)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(leftLabel)
                        .font(.caption.weight(.semibold))
                    Text("\(leftPresses) presses")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(leftHeldText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(rightLabel)
                        .font(.caption.weight(.semibold))
                    Text("\(rightPresses) presses")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(rightHeldText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
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
                .frame(maxWidth: .infinity)
                .frame(height: barHeight)
            HStack {
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(heldText)
                    .font(.system(size: 8, weight: .regular, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
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
