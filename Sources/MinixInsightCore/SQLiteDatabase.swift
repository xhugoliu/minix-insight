import Foundation
import SQLite3

public enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "Open database failed: \(message)"
        case .prepareFailed(let message):
            return "Prepare statement failed: \(message)"
        case .stepFailed(let message):
            return "Execute statement failed: \(message)"
        }
    }
}

public final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "minix-insight.sqlite")

    public init(url: URL) throws {
        try AppPaths.ensureDirectories()
        if sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            throw DatabaseError.openFailed(lastError)
        }
        try migrate()
    }

    deinit {
        sqlite3_close(handle)
    }

    public func insert(_ event: TelemetryEvent) throws {
        try queue.sync {
            let sql = """
            INSERT INTO events (
                host_time_iso, host_time_ns, qmk_time_ms, seq,
                row, col, pressed, layer, keycode
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            try withStatement(sql) { statement in
                sqlite3_bind_text(statement, 1, formatter.string(from: event.hostTime), -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(statement, 2, event.hostTimeNs)
                sqlite3_bind_int64(statement, 3, Int64(event.qmkTimeMs))
                sqlite3_bind_int64(statement, 4, Int64(event.sequence))
                sqlite3_bind_int(statement, 5, Int32(event.row))
                sqlite3_bind_int(statement, 6, Int32(event.col))
                sqlite3_bind_int(statement, 7, event.pressed ? 1 : 0)
                sqlite3_bind_int(statement, 8, Int32(event.layer))
                sqlite3_bind_int(statement, 9, Int32(event.keycode))
                try stepDone(statement)
            }
        }
    }

    public func todayPressCount() throws -> Int {
        try countPresses(since: Calendar.current.startOfDay(for: Date()))
    }

    public func todayHeldMs() throws -> Int64 {
        try heldMs(since: Calendar.current.startOfDay(for: Date()))
    }

    public func countPresses(since start: Date) throws -> Int {
        try queue.sync {
            let startNs = Int64(start.timeIntervalSince1970 * 1_000_000_000)
            return try scalarInt(
                "SELECT COUNT(*) FROM events WHERE pressed = 1 AND host_time_ns >= ?;",
                bind: { statement in sqlite3_bind_int64(statement, 1, startNs) }
            )
        }
    }

    public func heldMs(since start: Date) throws -> Int64 {
        let events = try eventsSince(start)
        var downAt: [String: UInt32] = [:]
        var total: Int64 = 0

        for event in events {
            let key = "\(event.row),\(event.col)"
            if event.pressed {
                downAt[key] = event.qmkTimeMs
            } else if let startedAt = downAt.removeValue(forKey: key) {
                total += Int64(elapsedMs(from: startedAt, to: event.qmkTimeMs))
            }
        }

        return total
    }

    public func summary(since start: Date) throws -> [KeySummary] {
        let events = try eventsSince(start)
        var pressCounts: [String: Int] = [:]
        var heldTotals: [String: Int64] = [:]
        var downAt: [String: UInt32] = [:]

        for event in events {
            let key = "\(event.row),\(event.col)"
            if event.pressed {
                if downAt[key] == nil {
                    pressCounts[key, default: 0] += 1
                    downAt[key] = event.qmkTimeMs
                }
            } else if let startedAt = downAt.removeValue(forKey: key) {
                heldTotals[key, default: 0] += Int64(elapsedMs(from: startedAt, to: event.qmkTimeMs))
            }
        }

        var result: [KeySummary] = []
        for row in 0..<6 {
            for col in 0..<5 {
                let key = "\(row),\(col)"
                result.append(
                    KeySummary(
                        row: row,
                        col: col,
                        pressCount: pressCounts[key, default: 0],
                        heldMs: heldTotals[key, default: 0]
                    )
                )
            }
        }
        return result
    }

    public func exportTodayCSV() throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let output = AppPaths.exportsDirectory.appendingPathComponent("minix-events-\(dateFormatter.string(from: Date())).csv")
        let events = try eventsSince(Calendar.current.startOfDay(for: Date()))

        var lines = ["host_time_iso,host_time_ns,qmk_time_ms,seq,row,col,pressed,layer,keycode"]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for event in events {
            lines.append(
                [
                    iso.string(from: event.hostTime),
                    String(event.hostTimeNs),
                    String(event.qmkTimeMs),
                    String(event.sequence),
                    String(event.row),
                    String(event.col),
                    event.pressed ? "1" : "0",
                    String(event.layer),
                    String(event.keycode),
                ].joined(separator: ",")
            )
        }

        try lines.joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)
        return output
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            host_time_iso TEXT NOT NULL,
            host_time_ns INTEGER NOT NULL,
            qmk_time_ms INTEGER NOT NULL,
            seq INTEGER NOT NULL,
            row INTEGER NOT NULL,
            col INTEGER NOT NULL,
            pressed INTEGER NOT NULL,
            layer INTEGER NOT NULL,
            keycode INTEGER NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_events_host_time_ns ON events(host_time_ns);")
        try execute("CREATE INDEX IF NOT EXISTS idx_events_matrix ON events(row, col, host_time_ns);")
    }

    private func eventsSince(_ start: Date) throws -> [TelemetryEvent] {
        try queue.sync {
            let startNs = Int64(start.timeIntervalSince1970 * 1_000_000_000)
            let sql = """
            SELECT host_time_iso, host_time_ns, qmk_time_ms, seq, row, col, pressed, layer, keycode
            FROM events
            WHERE host_time_ns >= ?
            ORDER BY host_time_ns ASC, id ASC;
            """
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var rows: [TelemetryEvent] = []

            try withStatement(sql) { statement in
                sqlite3_bind_int64(statement, 1, startNs)
                while sqlite3_step(statement) == SQLITE_ROW {
                    let timeString = String(cString: sqlite3_column_text(statement, 0))
                    rows.append(
                        TelemetryEvent(
                            hostTime: iso.date(from: timeString) ?? Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 1)) / 1_000_000_000),
                            hostTimeNs: sqlite3_column_int64(statement, 1),
                            qmkTimeMs: UInt32(sqlite3_column_int64(statement, 2)),
                            sequence: UInt32(sqlite3_column_int64(statement, 3)),
                            row: UInt8(sqlite3_column_int(statement, 4)),
                            col: UInt8(sqlite3_column_int(statement, 5)),
                            pressed: sqlite3_column_int(statement, 6) != 0,
                            layer: UInt8(sqlite3_column_int(statement, 7)),
                            keycode: UInt16(sqlite3_column_int(statement, 8))
                        )
                    )
                }
            }

            return rows
        }
    }

    private func execute(_ sql: String) throws {
        try queue.sync {
            try withStatement(sql) { statement in
                try stepDone(statement)
            }
        }
    }

    private func scalarInt(_ sql: String, bind: (OpaquePointer?) -> Void) throws -> Int {
        try withStatement(sql) { statement in
            bind(statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw DatabaseError.stepFailed(lastError)
            }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer?) throws -> T) throws -> T {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &statement, nil) != SQLITE_OK {
            throw DatabaseError.prepareFailed(lastError)
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        if sqlite3_step(statement) != SQLITE_DONE {
            throw DatabaseError.stepFailed(lastError)
        }
    }

    private func elapsedMs(from start: UInt32, to end: UInt32) -> UInt32 {
        if end >= start {
            return end - start
        }
        return (UInt32.max - start) + end + 1
    }

    private var lastError: String {
        if let message = sqlite3_errmsg(handle) {
            return String(cString: message)
        }
        return "unknown SQLite error"
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
