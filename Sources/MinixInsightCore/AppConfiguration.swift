import Foundation

public struct DeviceMatch: Equatable, Sendable {
    public let vendorID: Int
    public let productID: Int
    public let usagePage: Int
    public let usage: Int

    public init(vendorID: Int, productID: Int, usagePage: Int, usage: Int) {
        self.vendorID = vendorID
        self.productID = productID
        self.usagePage = usagePage
        self.usage = usage
    }

    var hidDictionary: [String: Any] {
        [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID,
            kIOHIDDeviceUsagePageKey as String: usagePage,
            kIOHIDDeviceUsageKey as String: usage,
        ]
    }
}

public struct KeyboardPresentation: Equatable, Sendable {
    public let leftRows: Range<Int>
    public let rightRows: Range<Int>

    public init(leftRows: Range<Int>, rightRows: Range<Int>) {
        self.leftRows = leftRows
        self.rightRows = rightRows
    }
}

public struct AppConfiguration: Equatable, Sendable {
    public let deviceName: String
    public let layout: KeyboardLayout
    public let deviceMatch: DeviceMatch
    public let presentation: KeyboardPresentation

    public init(
        deviceName: String,
        layout: KeyboardLayout,
        deviceMatch: DeviceMatch,
        presentation: KeyboardPresentation
    ) {
        self.deviceName = deviceName
        self.layout = layout
        self.deviceMatch = deviceMatch
        self.presentation = presentation
    }

    public static let miniX = AppConfiguration(
        deviceName: "miniX",
        layout: .miniX,
        deviceMatch: DeviceMatch(
            vendorID: 0x5262,
            productID: 0x4E4B,
            usagePage: 0xFF60,
            usage: 0x61
        ),
        presentation: KeyboardPresentation(leftRows: 0..<3, rightRows: 3..<6)
    )
}
