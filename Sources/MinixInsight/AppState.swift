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

    let databaseURL = AppPaths.databaseURL

    private let database: SQLiteDatabase
    private var collector: TelemetryCollector?
    private var refreshTimer: Timer?

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
            if event.pressed {
                todayPresses += 1
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func refreshStats() {
        do {
            todayPresses = try database.todayPressCount()
            todayHeldMs = try database.todayHeldMs()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
