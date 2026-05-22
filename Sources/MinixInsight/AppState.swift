import AppKit
import Foundation
import MinixInsightCore
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var status: CollectorStatus = .waiting
    @Published var isLogging = true
    @Published var todayPresses = 0
    @Published var todayHeldMs: Int64 = 0
    @Published var lastEventText = "No events yet"
    @Published var lastError: String?
    @Published var exportedURL: URL?
    @Published var keySummaries = AppState.blankSummaries()
    @Published var activeKeys: Set<String> = []

    let databaseURL = AppPaths.databaseURL

    private let database: SQLiteDatabase
    private var collector: TelemetryCollector?
    private var refreshTimer: Timer?
    private var activeQmkTimes: [String: UInt32] = [:]

    init() {
        do {
            database = try SQLiteDatabase(url: AppPaths.databaseURL)
        } catch {
            fatalError("Failed to open database: \(error.localizedDescription)")
        }

        collector = TelemetryCollector(
            onEvent: { [weak self] event in
                Task { @MainActor in
                    self?.handle(event)
                }
            },
            onStatus: { [weak self] status in
                Task { @MainActor in
                    self?.status = status
                }
            }
        )

        start()
        refreshStats()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStats() }
        }
    }

    func toggleLogging() {
        isLogging.toggle()
        if isLogging {
            start()
        } else {
            stop()
        }
    }

    func exportToday() {
        do {
            let url = try database.exportTodayCSV()
            exportedURL = url
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            lastError = error.localizedDescription
        }
    }

    func revealDatabase() {
        NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
    }

    func quit() {
        stop()
        NSApplication.shared.terminate(nil)
    }

    private func start() {
        isLogging = true
        collector?.start()
    }

    private func stop() {
        collector?.stop()
    }

    private func handle(_ event: TelemetryEvent) {
        do {
            try database.insert(event)
            lastEventText = "r\(event.row)c\(event.col) \(event.pressed ? "down" : "up")"
            updateSummary(with: event)
            if event.pressed {
                todayPresses += 1
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func refreshStats() {
        do {
            keySummaries = try database.summary(since: Calendar.current.startOfDay(for: Date()))
            todayPresses = keySummaries.reduce(0) { $0 + $1.pressCount }
            todayHeldMs = keySummaries.reduce(0) { $0 + $1.heldMs }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func updateSummary(with event: TelemetryEvent) {
        let row = Int(event.row)
        let col = Int(event.col)
        let key = Self.keyID(row: row, col: col)

        if event.pressed {
            activeKeys.insert(key)
            activeQmkTimes[key] = event.qmkTimeMs
            updateKey(row: row, col: col) { summary in
                KeySummary(row: row, col: col, pressCount: summary.pressCount + 1, heldMs: summary.heldMs)
            }
            return
        }

        activeKeys.remove(key)
        guard let startedAt = activeQmkTimes.removeValue(forKey: key) else {
            return
        }

        let held = Int64(elapsedMs(from: startedAt, to: event.qmkTimeMs))
        todayHeldMs += held
        updateKey(row: row, col: col) { summary in
            KeySummary(row: row, col: col, pressCount: summary.pressCount, heldMs: summary.heldMs + held)
        }
    }

    private func updateKey(row: Int, col: Int, transform: (KeySummary) -> KeySummary) {
        guard let index = keySummaries.firstIndex(where: { $0.row == row && $0.col == col }) else {
            return
        }
        keySummaries[index] = transform(keySummaries[index])
    }

    private func elapsedMs(from start: UInt32, to end: UInt32) -> UInt32 {
        if end >= start {
            return end - start
        }
        return (UInt32.max - start) + end + 1
    }

    static func keyID(row: Int, col: Int) -> String {
        "\(row),\(col)"
    }

    private static func blankSummaries() -> [KeySummary] {
        var result: [KeySummary] = []
        for row in 0..<6 {
            for col in 0..<5 {
                result.append(KeySummary(row: row, col: col, pressCount: 0, heldMs: 0))
            }
        }
        return result
    }
}
