import Foundation
import Testing
@testable import MinixInsightCore

struct SQLiteDatabaseTests {
    @Test func calculatesSummaryAndHeldTimeAcrossEvents() throws {
        let database = try makeDatabase()

        try database.insert(event(hostTimeNs: 1_000, qmkTimeMs: 100, row: 0, col: 0, pressed: true))
        try database.insert(event(hostTimeNs: 2_000, qmkTimeMs: 160, row: 0, col: 0, pressed: false))
        try database.insert(event(hostTimeNs: 3_000, qmkTimeMs: 200, row: 1, col: 2, pressed: true))
        try database.insert(event(hostTimeNs: 4_000, qmkTimeMs: 250, row: 1, col: 2, pressed: false))

        let snapshot = try database.summarySnapshot(since: Date(timeIntervalSince1970: 0))
        let key00 = try #require(snapshot.keySummaries.first(where: { $0.row == 0 && $0.col == 0 }))
        let key12 = try #require(snapshot.keySummaries.first(where: { $0.row == 1 && $0.col == 2 }))

        #expect(snapshot.pressCount == 2)
        #expect(snapshot.heldMs == 110)
        #expect(key00.pressCount == 1)
        #expect(key00.heldMs == 60)
        #expect(key12.pressCount == 1)
        #expect(key12.heldMs == 50)
        #expect(try database.heldMs(since: Date(timeIntervalSince1970: 0)) == 110)
    }

    @Test func ignoresDuplicateDownUntilKeyReleased() throws {
        let database = try makeDatabase()

        try database.insert(event(hostTimeNs: 1_000, qmkTimeMs: 100, row: 2, col: 3, pressed: true))
        try database.insert(event(hostTimeNs: 2_000, qmkTimeMs: 120, row: 2, col: 3, pressed: true))
        try database.insert(event(hostTimeNs: 3_000, qmkTimeMs: 160, row: 2, col: 3, pressed: false))

        let snapshot = try database.summarySnapshot(since: Date(timeIntervalSince1970: 0))
        let key = try #require(snapshot.keySummaries.first(where: { $0.row == 2 && $0.col == 3 }))

        #expect(snapshot.pressCount == 1)
        #expect(snapshot.heldMs == 60)
        #expect(key.pressCount == 1)
        #expect(key.heldMs == 60)
    }

    @Test func handlesQmkTimerWraparound() throws {
        let database = try makeDatabase()

        try database.insert(event(hostTimeNs: 1_000, qmkTimeMs: UInt32.max - 10, row: 4, col: 1, pressed: true))
        try database.insert(event(hostTimeNs: 2_000, qmkTimeMs: 20, row: 4, col: 1, pressed: false))

        let snapshot = try database.summarySnapshot(since: Date(timeIntervalSince1970: 0))
        let key = try #require(snapshot.keySummaries.first(where: { $0.row == 4 && $0.col == 1 }))

        #expect(snapshot.heldMs == 31)
        #expect(key.heldMs == 31)
    }

    @Test func exportsSummaryCsv() throws {
        let database = try makeDatabase()
        try database.insert(event(hostTimeNs: 1_000, qmkTimeMs: 100, row: 0, col: 1, pressed: true))
        try database.insert(event(hostTimeNs: 2_000, qmkTimeMs: 180, row: 0, col: 1, pressed: false))

        let url = try database.exportSummaryCSV(since: Date(timeIntervalSince1970: 0))
        let content = try String(contentsOf: url)

        #expect(content.contains("row,col,press_count,held_ms"))
        #expect(content.contains("0,1,1,80"))
    }

    @Test func buildsDailySummariesAcrossSevenDays() throws {
        let database = try makeDatabase()
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))

        try database.insert(event(on: start, secondsIntoDay: 10, qmkTimeMs: 100, row: 0, col: 0, pressed: true))
        try database.insert(event(on: start, secondsIntoDay: 20, qmkTimeMs: 160, row: 0, col: 0, pressed: false))

        let day3 = try #require(calendar.date(byAdding: .day, value: 3, to: start))
        try database.insert(event(on: day3, secondsIntoDay: 5, qmkTimeMs: 200, row: 1, col: 1, pressed: true))
        try database.insert(event(on: day3, secondsIntoDay: 15, qmkTimeMs: 260, row: 1, col: 1, pressed: false))

        let summaries = try database.dailySummaries(since: start, days: 7, calendar: calendar)

        #expect(summaries.count == 7)
        #expect(summaries[0].pressCount == 1)
        #expect(summaries[0].heldMs == 60)
        #expect(summaries[1].pressCount == 0)
        #expect(summaries[3].pressCount == 1)
        #expect(summaries[3].heldMs == 60)
        #expect(summaries[6].pressCount == 0)
    }

    private func makeDatabase() throws -> SQLiteDatabase {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try SQLiteDatabase(url: directory.appendingPathComponent("test.sqlite3"))
    }

    private func event(
        hostTimeNs: Int64,
        qmkTimeMs: UInt32,
        row: UInt8,
        col: UInt8,
        pressed: Bool,
        layer: UInt8 = 0,
        keycode: UInt16 = 0
    ) -> TelemetryEvent {
        TelemetryEvent(
            hostTime: Date(timeIntervalSince1970: TimeInterval(hostTimeNs) / 1_000_000_000),
            hostTimeNs: hostTimeNs,
            qmkTimeMs: qmkTimeMs,
            sequence: qmkTimeMs,
            row: row,
            col: col,
            pressed: pressed,
            layer: layer,
            keycode: keycode
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
