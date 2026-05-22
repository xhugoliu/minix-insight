import Foundation

public struct TelemetryEvent: Equatable, Sendable {
    public let hostTime: Date
    public let hostTimeNs: Int64
    public let qmkTimeMs: UInt32
    public let sequence: UInt32
    public let row: UInt8
    public let col: UInt8
    public let pressed: Bool
    public let layer: UInt8
    public let keycode: UInt16

    public init(hostTime: Date, hostTimeNs: Int64, qmkTimeMs: UInt32, sequence: UInt32, row: UInt8, col: UInt8, pressed: Bool, layer: UInt8, keycode: UInt16) {
        self.hostTime = hostTime
        self.hostTimeNs = hostTimeNs
        self.qmkTimeMs = qmkTimeMs
        self.sequence = sequence
        self.row = row
        self.col = col
        self.pressed = pressed
        self.layer = layer
        self.keycode = keycode
    }
}

public struct KeySummary: Equatable, Sendable {
    public let row: Int
    public let col: Int
    public let pressCount: Int
    public let heldMs: Int64

    public init(row: Int, col: Int, pressCount: Int, heldMs: Int64) {
        self.row = row
        self.col = col
        self.pressCount = pressCount
        self.heldMs = heldMs
    }
}
