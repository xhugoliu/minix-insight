import Foundation

public enum TelemetryPacket {
    public static let reportSize = 32
    private static let magic0 = UInt8(ascii: "K")
    private static let magic1 = UInt8(ascii: "S")

    public static func parse(_ bytes: [UInt8], hostTime: Date = Date()) -> TelemetryEvent? {
        guard let offset = eventOffset(bytes) else {
            return nil
        }

        guard bytes.count >= offset + reportSize else {
            return nil
        }

        let version = bytes[offset + 2]
        let type = bytes[offset + 3]
        guard version == 1, type == 1 else {
            return nil
        }

        return TelemetryEvent(
            hostTime: hostTime,
            hostTimeNs: Int64(Date().timeIntervalSince1970 * 1_000_000_000),
            qmkTimeMs: readUInt32(bytes, offset + 8),
            sequence: readUInt32(bytes, offset + 14),
            row: bytes[offset + 4],
            col: bytes[offset + 5],
            pressed: bytes[offset + 6] != 0,
            layer: bytes[offset + 7],
            keycode: readUInt16(bytes, offset + 12)
        )
    }

    private static func eventOffset(_ bytes: [UInt8]) -> Int? {
        if bytes.count >= 2, bytes[0] == magic0, bytes[1] == magic1 {
            return 0
        }

        if bytes.count >= 3, bytes[1] == magic0, bytes[2] == magic1 {
            return 1
        }

        return nil
    }

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
