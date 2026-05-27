import MinixInsightCore
import SwiftUI

struct KeyboardLayoutView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            half(title: "Left", rows: appState.configuration.presentation.leftRows)
            half(title: "Right", rows: appState.configuration.presentation.rightRows)
        }
    }

    private func half(title: String, rows: Range<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 5) {
                ForEach(Array(rows), id: \.self) { row in
                    HStack(spacing: 5) {
                        ForEach(0..<appState.configuration.layout.columns, id: \.self) { col in
                            KeyTileView(
                                summary: summary(row: row, col: col),
                                maxPressCount: maxPressCount,
                                isActive: appState.activeKeys.contains(AppState.keyID(row: row, col: col))
                            )
                        }
                    }
                    .frame(width: 260, height: 44)
                }
            }
            .frame(width: 260, height: 142)
        }
        .frame(width: 260, height: 166, alignment: .topLeading)
    }

    private var maxPressCount: Int {
        max(appState.keySummaries.map(\.pressCount).max() ?? 0, 1)
    }

    private func summary(row: Int, col: Int) -> KeySummary {
        appState.keySummaries.first { $0.row == row && $0.col == col }
            ?? KeySummary(row: row, col: col, pressCount: 0, heldMs: 0)
    }
}

private struct KeyTileView: View {
    let summary: KeySummary
    let maxPressCount: Int
    let isActive: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text("r\(summary.row)c\(summary.col)")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text("\(summary.pressCount)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(formatDuration(summary.heldMs))
                .font(.system(size: 8, weight: .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(width: 48, height: 44)
        .background(tileBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isActive ? Color.green.opacity(0.8) : Color.secondary.opacity(0.18), lineWidth: isActive ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var tileBackground: some ShapeStyle {
        let intensity = Double(summary.pressCount) / Double(maxPressCount)
        let opacity = 0.08 + intensity * 0.32
        return isActive ? Color.green.opacity(0.22) : Color.accentColor.opacity(opacity)
    }

    private func formatDuration(_ milliseconds: Int64) -> String {
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
