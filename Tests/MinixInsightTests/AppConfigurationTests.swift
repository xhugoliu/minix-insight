import Testing
@testable import MinixInsightCore

struct AppConfigurationTests {
    @Test func miniXConfigurationCapturesExpectedLayoutAndPresentation() {
        let configuration = AppConfiguration.miniX

        #expect(configuration.deviceName == "miniX")
        #expect(configuration.layout.rows == 6)
        #expect(configuration.layout.columns == 5)
        #expect(configuration.presentation.leftRows == 0..<3)
        #expect(configuration.presentation.rightRows == 3..<6)
    }

    @Test func miniXConfigurationCapturesExpectedHidMatch() {
        let match = AppConfiguration.miniX.deviceMatch

        #expect(match.vendorID == 0x5262)
        #expect(match.productID == 0x4E4B)
        #expect(match.usagePage == 0xFF60)
        #expect(match.usage == 0x61)
    }
}
