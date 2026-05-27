import Testing
@testable import MinixInsightCore

struct TelemetryCollectorStatusTests {
    @Test func waitingStatusExposesHelpfulDetail() {
        let initial = CollectorStatus.waiting(.initial)
        let disconnected = CollectorStatus.waiting(.disconnected)

        #expect(initial.title == "Waiting for keyboard")
        #expect(initial.detail?.contains("Connect miniX") == true)
        #expect(disconnected.title == "Keyboard disconnected")
        #expect(disconnected.detail?.contains("Reconnect miniX") == true)
    }

    @Test func issueStatusDistinguishesBusyAndProtocolProblems() {
        let busy = CollectorStatus.issue(.deviceOpenFailed(code: -1))
        let unsupported = CollectorStatus.issue(.unsupportedTelemetry(length: 64))

        #expect(busy.title == "Raw HID busy")
        #expect(busy.detail?.contains("Close Vial") == true)
        #expect(unsupported.title == "Unsupported telemetry")
        #expect(unsupported.detail?.contains("64-byte telemetry report") == true)
        #expect(busy.showsIssue)
        #expect(unsupported.showsIssue)
    }
}
