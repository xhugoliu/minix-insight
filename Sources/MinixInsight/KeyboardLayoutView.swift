import MinixInsightCore
import SwiftUI

struct KeyboardLayoutView: View {
    @EnvironmentObject private var appState: AppState
    let metricMode: PanelMetricMode

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(proxy.size.width, 320)
            let columns = appState.configuration.layout.columns
            let halfSpacing: CGFloat = 14
            let tileSpacing: CGFloat = 5
            let halfWidth = max(140, (availableWidth - halfSpacing) / 2)
            let tileWidth = max(24, min(48, (halfWidth - tileSpacing * CGFloat(columns - 1)) / CGFloat(columns)))
            let tileHeight = max(34, min(44, tileWidth * 0.92))

            HStack(alignment: .top, spacing: halfSpacing) {
                half(title: "Left", rows: appState.configuration.presentation.leftRows, tileWidth: tileWidth, tileHeight: tileHeight)
                half(title: "Right", rows: appState.configuration.presentation.rightRows, tileWidth: tileWidth, tileHeight: tileHeight)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(height: 156)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func half(title: String, rows: Range<Int>, tileWidth: CGFloat, tileHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 5) {
                ForEach(Array(rows), id: \.self) { row in
                    HStack(spacing: 5) {
                        ForEach(0..<appState.configuration.layout.columns, id: \.self) { col in
                            KeyTileView(
                                summary: summary(row: row, col: col),
                                maxPressCount: maxPressCount,
                                maxHeldMs: maxHeldMs,
                                isActive: appState.activeKeys.contains(AppState.keyID(row: row, col: col)),
                                metricMode: metricMode,
                                tileWidth: tileWidth,
                                tileHeight: tileHeight
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var maxPressCount: Int {
        max(appState.keySummaries.map(\.pressCount).max() ?? 0, 1)
    }

    private var maxHeldMs: Int64 {
        max(appState.keySummaries.map(\.heldMs).max() ?? 0, 1)
    }

    private func summary(row: Int, col: Int) -> KeySummary {
        appState.keySummaries.first { $0.row == row && $0.col == col }
            ?? KeySummary(row: row, col: col, pressCount: 0, heldMs: 0)
    }
}

private struct KeyTileView: View {
    let summary: KeySummary
    let maxPressCount: Int
    let maxHeldMs: Int64
    let isActive: Bool
    let metricMode: PanelMetricMode
    let tileWidth: CGFloat
    let tileHeight: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            Text("r\(summary.row)c\(summary.col)")
                .font(.system(size: max(7, tileWidth * 0.16), weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            switch metricMode {
            case .combined:
                Text("\(summary.pressCount)")
                    .font(.system(size: max(11, tileWidth * 0.28), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(formatDuration(summary.heldMs))
                    .font(.system(size: max(7, tileWidth * 0.16), weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            case .press:
                Text("\(summary.pressCount)")
                    .font(.system(size: max(11, tileWidth * 0.28), weight: .semibold, design: .rounded))
                    .monospacedDigit()
            case .held:
                Text(formatDuration(summary.heldMs))
                    .font(.system(size: max(11, tileWidth * 0.26), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
        }
        .frame(width: tileWidth, height: tileHeight)
        .background(tileBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isActive ? Color.green.opacity(0.8) : Color.secondary.opacity(0.18), lineWidth: isActive ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var tileBackground: some ShapeStyle {
        let intensity = heatmapIntensity
        let opacity = 0.08 + intensity * 0.32
        return isActive ? Color.green.opacity(0.22) : Color.accentColor.opacity(opacity)
    }

    private var heatmapIntensity: Double {
        let pressIntensity = Double(summary.pressCount) / Double(maxPressCount)
        let heldIntensity = Double(summary.heldMs) / Double(maxHeldMs)

        switch metricMode {
        case .combined:
            return pressIntensity * 0.7 + heldIntensity * 0.3
        case .press:
            return pressIntensity
        case .held:
            return heldIntensity
        }
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
