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
            actions
            if let error = appState.lastError {
                Divider()
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(appState.status.isConnected && appState.isLogging ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text("Minix Insight")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text("Held")
                    .foregroundStyle(.secondary)
                Text(formatDuration(appState.todayHeldMs))
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

    private var actions: some View {
        VStack(spacing: 8) {
            Button(appState.isLogging ? "Pause Logging" : "Resume Logging") {
                appState.toggleLogging()
            }
            Button("Export Today CSV") {
                appState.exportToday()
            }
            Button("Reveal Database") {
                appState.revealDatabase()
            }
            Button("Quit") {
                appState.quit()
            }
        }
    }

    private var statusText: String {
        if !appState.isLogging {
            return "Paused"
        }

        switch appState.status {
        case .connected(let name):
            return name
        case .waiting:
            return "Waiting for keyboard"
        case .stopped:
            return "Paused"
        case .error(let message):
            return message
        }
    }

    private func formatDuration(_ milliseconds: Int64) -> String {
        let seconds = Double(milliseconds) / 1000
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        return String(format: "%.1fmin", seconds / 60)
    }
}
