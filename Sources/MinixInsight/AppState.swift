import AppKit
import Foundation
import MinixInsightCore
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    private static let layout: KeyboardLayout = .miniX

    @Published var status: CollectorStatus = .waiting
    @Published var isLogging = true
    @Published var todayPresses = 0
    @Published var last7DaysPresses = 0
    @Published var todayHeldMs: Int64 = 0
    @Published var last7DaysHeldMs: Int64 = 0
    @Published var lastEventText = "No events yet"
    @Published var lastError: String?
    @Published var exportedURL: URL?
    @Published var keySummaries = SummarySnapshot.empty(layout: AppState.layout).keySummaries
    @Published var activeKeys: Set<String> = []

    let databaseURL = AppPaths.databaseURL

    private let database: SQLiteDatabase
    private var collector: TelemetryCollector?
    private var refreshTimer: Timer?
    private var summaryTracker = LiveSummaryTracker(layout: AppState.layout)

    init() {
        do {
            database = try SQLiteDatabase(url: AppPaths.databaseURL, layout: Self.layout)
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

    func exportSummary() {
        do {
            let url = try database.exportSummaryCSV(since: Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date())
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
        summaryTracker.reset(snapshot: summaryTracker.snapshot)
        syncPublishedSummary()
    }

    private func handle(_ event: TelemetryEvent) {
        do {
            try database.insert(event)
            lastEventText = "r\(event.row)c\(event.col) \(event.pressed ? "down" : "up")"
            summaryTracker.apply(event)
            syncPublishedSummary()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func refreshStats() {
        do {
            let calendar = Calendar.current
            let todayStart = calendar.startOfDay(for: Date())
            let last7DaysStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart

            let todaySnapshot = try database.summarySnapshot(since: todayStart)
            let last7DaysSnapshot = try database.summarySnapshot(since: last7DaysStart)

            summaryTracker.rebase(snapshot: todaySnapshot)
            syncPublishedSummary()
            last7DaysPresses = last7DaysSnapshot.pressCount
            last7DaysHeldMs = last7DaysSnapshot.heldMs
        } catch {
            lastError = error.localizedDescription
        }
    }

    static func keyID(row: Int, col: Int) -> String {
        LiveSummaryTracker.keyID(row: row, col: col)
    }

    private func syncPublishedSummary() {
        let snapshot = summaryTracker.snapshot
        keySummaries = snapshot.keySummaries
        todayPresses = snapshot.pressCount
        todayHeldMs = snapshot.heldMs
        activeKeys = summaryTracker.activeKeys
    }
}
