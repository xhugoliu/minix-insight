import Foundation
import Testing
@testable import MinixInsightCore

struct TelemetrySummaryTests {
    @Test func liveSummaryTrackerTracksActiveKeysAndTotals() {
        var tracker = LiveSummaryTracker(layout: .miniX)

        tracker.apply(event(qmkTimeMs: 50, row: 0, col: 0, pressed: true))
        #expect(tracker.snapshot.pressCount == 1)
        #expect(tracker.snapshot.heldMs == 0)
        #expect(tracker.activeKeys.contains(LiveSummaryTracker.keyID(row: 0, col: 0)))

        tracker.apply(event(qmkTimeMs: 80, row: 0, col: 0, pressed: false))
        #expect(tracker.snapshot.pressCount == 1)
        #expect(tracker.snapshot.heldMs == 30)
        #expect(!tracker.activeKeys.contains(LiveSummaryTracker.keyID(row: 0, col: 0)))
    }

    @Test func summaryCalculatorBuildsSnapshotForWholeRange() {
        let snapshot = SummaryCalculator.snapshot(
            from: [
                event(qmkTimeMs: 100, row: 1, col: 1, pressed: true),
                event(qmkTimeMs: 180, row: 1, col: 1, pressed: false),
                event(qmkTimeMs: 200, row: 2, col: 4, pressed: true),
                event(qmkTimeMs: 260, row: 2, col: 4, pressed: false),
            ],
            layout: .miniX
        )

        let key11 = snapshot.keySummaries.first { $0.row == 1 && $0.col == 1 }
        let key24 = snapshot.keySummaries.first { $0.row == 2 && $0.col == 4 }

        #expect(snapshot.pressCount == 2)
        #expect(snapshot.heldMs == 140)
        #expect(key11?.pressCount == 1)
        #expect(key11?.heldMs == 80)
        #expect(key24?.pressCount == 1)
        #expect(key24?.heldMs == 60)
    }

    @Test func dayScopedTrackerRollsToNewDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day1 = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let day2 = try #require(calendar.date(byAdding: .day, value: 1, to: day1))
        var tracker = DayScopedLiveSummaryTracker(layout: .miniX, dayStart: day1, calendar: calendar)

        tracker.apply(event(on: day1, secondsIntoDay: 10, qmkTimeMs: 100, row: 0, col: 0, pressed: true))
        tracker.apply(event(on: day1, secondsIntoDay: 11, qmkTimeMs: 160, row: 0, col: 0, pressed: false))
        #expect(tracker.snapshot.pressCount == 1)
        #expect(tracker.snapshot.heldMs == 60)

        let didRollDay = tracker.apply(event(on: day2, secondsIntoDay: 1, qmkTimeMs: 200, row: 1, col: 1, pressed: true))
        tracker.apply(event(on: day2, secondsIntoDay: 2, qmkTimeMs: 260, row: 1, col: 1, pressed: false))

        #expect(didRollDay)
        #expect(tracker.dayStart == day2)
        #expect(tracker.snapshot.pressCount == 1)
        #expect(tracker.snapshot.heldMs == 60)
        #expect(tracker.snapshot.keySummaries.first { $0.row == 0 && $0.col == 0 }?.pressCount == 0)
        #expect(tracker.snapshot.keySummaries.first { $0.row == 1 && $0.col == 1 }?.pressCount == 1)
    }

    @Test func ignoresImplausibleHoldAfterDeviceTimerRestart() {
        let snapshot = SummaryCalculator.snapshot(
            from: [
                event(qmkTimeMs: 60_000, row: 2, col: 2, pressed: true),
                event(qmkTimeMs: 10_000, row: 2, col: 2, pressed: false),
            ],
            layout: .miniX
        )

        #expect(snapshot.pressCount == 1)
        #expect(snapshot.heldMs == 0)
        #expect(snapshot.keySummaries.first { $0.row == 2 && $0.col == 2 }?.heldMs == 0)
    }

    private func event(qmkTimeMs: UInt32, row: UInt8, col: UInt8, pressed: Bool) -> TelemetryEvent {
        TelemetryEvent(
            hostTime: Date(timeIntervalSince1970: 0),
            hostTimeNs: Int64(qmkTimeMs) * 1_000_000,
            qmkTimeMs: qmkTimeMs,
            sequence: qmkTimeMs,
            row: row,
            col: col,
            pressed: pressed,
            layer: 0,
            keycode: 0
        )
    }

    private func event(
        on dayStart: Date,
        secondsIntoDay: TimeInterval,
        qmkTimeMs: UInt32,
        row: UInt8,
        col: UInt8,
        pressed: Bool
    ) -> TelemetryEvent {
        let hostTime = dayStart.addingTimeInterval(secondsIntoDay)
        return TelemetryEvent(
            hostTime: hostTime,
            hostTimeNs: Int64(hostTime.timeIntervalSince1970 * 1_000_000_000),
            qmkTimeMs: qmkTimeMs,
            sequence: qmkTimeMs,
            row: row,
            col: col,
            pressed: pressed,
            layer: 0,
            keycode: 0
        )
    }
}
