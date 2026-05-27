import AppKit
import Foundation
import MinixInsightCore
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    private static let configuration = AppConfiguration.miniX
    private static let summaryRangeDays = 7

    @Published var status: CollectorStatus = .waiting(.initial)
    @Published var isLogging = true
    @Published var todayPresses = 0
    @Published var last7DaysPresses = 0
    @Published var todayHeldMs: Int64 = 0
    @Published var last7DaysHeldMs: Int64 = 0
    @Published var dailySummaries: [DailySummary] = []
    @Published var lastEventText = "No events yet"
    @Published var appError: String?
    @Published var exportedURL: URL?
    @Published var keySummaries = SummarySnapshot.empty(layout: AppState.configuration.layout).keySummaries
    @Published var activeKeys: Set<String> = []

    let databaseURL = AppPaths.databaseURL
    let configuration = AppState.configuration

    private let database: SQLiteDatabase
    private let persistenceQueue = DispatchQueue(label: "minix-insight.persistence", qos: .utility)
    private var collector: TelemetryCollector?
    private var eventBatcher: TelemetryEventBatcher?
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var summaryTracker = LiveSummaryTracker(layout: AppState.configuration.layout)
    private var bootstrapEvents: [TelemetryEvent] = []
    private var didLoadInitialSnapshot = false

    init() {
        do {
            database = try SQLiteDatabase(url: AppPaths.databaseURL, layout: Self.configuration.layout)
        } catch {
            fatalError("Failed to open database: \(error.localizedDescription)")
        }

        let eventBatcher = TelemetryEventBatcher { [weak self] events in
            Task { @MainActor in
                self?.handle(events)
            }
        }
        self.eventBatcher = eventBatcher

        collector = TelemetryCollector(
            configuration: Self.configuration,
            onEvent: { event in
                eventBatcher.enqueue(event)
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
            appError = error.localizedDescription
        }
    }

    func exportSummary() {
        do {
            let url = try database.exportSummaryCSV(since: summaryStartDate)
            exportedURL = url
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            appError = error.localizedDescription
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

    private func handle(_ events: [TelemetryEvent]) {
        appError = nil
        guard let lastEvent = events.last else { return }

        if !didLoadInitialSnapshot {
            bootstrapEvents.append(contentsOf: events)
        }
        persist(events)
        lastEventText = "r\(lastEvent.row)c\(lastEvent.col) \(lastEvent.pressed ? "down" : "up")"
        for event in events {
            summaryTracker.apply(event)
        }
        syncPublishedSummary()
    }

    private func refreshStats() {
        refreshTask?.cancel()

        let database = self.database
        let todayStartDate = self.todayStartDate
        let summaryStartDate = self.summaryStartDate
        let days = Self.summaryRangeDays

        refreshTask = Task.detached(priority: .utility) { [weak self] in
            do {
                let dashboard = try database.dashboardSnapshot(
                    since: summaryStartDate,
                    todayStart: todayStartDate,
                    days: days
                )

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyRefreshedStats(
                        todaySnapshot: dashboard.today,
                        last7DaysSnapshot: dashboard.range,
                        dailySummaries: dashboard.dailySummaries
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.appError = error.localizedDescription
                }
            }
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

    private func applyRefreshedStats(
        todaySnapshot: SummarySnapshot,
        last7DaysSnapshot: SummarySnapshot,
        dailySummaries: [DailySummary]
    ) {
        if !didLoadInitialSnapshot {
            var tracker = LiveSummaryTracker(layout: configuration.layout, snapshot: todaySnapshot)
            for event in bootstrapEvents {
                tracker.apply(event)
            }
            bootstrapEvents.removeAll()
            summaryTracker = tracker
            didLoadInitialSnapshot = true
            syncPublishedSummary()
        }

        last7DaysPresses = last7DaysSnapshot.pressCount
        last7DaysHeldMs = last7DaysSnapshot.heldMs
        self.dailySummaries = dailySummaries
        appError = nil
    }

    private func persist(_ events: [TelemetryEvent]) {
        let database = self.database
        persistenceQueue.async { [weak self] in
            do {
                for event in events {
                    try database.insert(event)
                }
            } catch {
                Task { @MainActor in
                    self?.appError = error.localizedDescription
                }
            }
        }
    }

    var statusDetail: String? {
        appError ?? status.detail
    }

    var statusShowsIssue: Bool {
        appError != nil || status.showsIssue
    }

    private var todayStartDate: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var summaryStartDate: Date {
        Calendar.current.date(byAdding: .day, value: -(Self.summaryRangeDays - 1), to: todayStartDate) ?? todayStartDate
    }
}
