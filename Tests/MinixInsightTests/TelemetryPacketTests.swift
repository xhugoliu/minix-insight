import Foundation
import Testing
@testable import MinixInsightCore

@Test func parsesKeyboardTelemetryPacket() throws {
    var packet = Array(repeating: UInt8(0), count: TelemetryPacket.reportSize)
    packet[0] = UInt8(ascii: "K")
    packet[1] = UInt8(ascii: "S")
    packet[2] = 1
    packet[3] = 1
    packet[4] = 1
    packet[5] = 2
    packet[6] = 1
    packet[7] = 3
    packet[8] = 0x78
    packet[9] = 0x56
    packet[10] = 0x34
    packet[11] = 0x12
    packet[12] = 0x22
    packet[13] = 0x11
    packet[14] = 0x04
    packet[15] = 0x03
    packet[16] = 0x02
    packet[17] = 0x01

    let event = try #require(TelemetryPacket.parse(packet))

    #expect(event.row == 1)
    #expect(event.col == 2)
    #expect(event.pressed)
    #expect(event.layer == 3)
    #expect(event.qmkTimeMs == 0x12345678)
    #expect(event.keycode == 0x1122)
    #expect(event.sequence == 0x01020304)
}

@Test func parsesPacketWithLeadingReportId() throws {
    var packet = Array(repeating: UInt8(0), count: TelemetryPacket.reportSize + 1)
    packet[1] = UInt8(ascii: "K")
    packet[2] = UInt8(ascii: "S")
    packet[3] = 1
    packet[4] = 1
    packet[5] = 4
    packet[6] = 0
    packet[7] = 0
    packet[8] = 2

    let event = try #require(TelemetryPacket.parse(packet))

    #expect(event.row == 4)
    #expect(event.col == 0)
    #expect(!event.pressed)
    #expect(event.layer == 2)
}
