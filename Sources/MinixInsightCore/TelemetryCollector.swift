import Foundation
@preconcurrency import IOKit.hid

public enum CollectorWaitingReason: Equatable, Sendable {
    case initial
    case disconnected
}

public enum CollectorIssue: Equatable, Sendable {
    case managerOpenFailed(code: Int32)
    case deviceOpenFailed(code: Int32)
    case unsupportedTelemetry(length: Int)

    public var title: String {
        switch self {
        case .managerOpenFailed:
            return "Raw HID unavailable"
        case .deviceOpenFailed:
            return "Raw HID busy"
        case .unsupportedTelemetry:
            return "Unsupported telemetry"
        }
    }

    public var detail: String {
        switch self {
        case .managerOpenFailed(let code):
            return "Could not start the macOS HID manager (\(codeLabel(code))). Replug miniX or restart the app."
        case .deviceOpenFailed(let code):
            return "Could not open the keyboard Raw HID interface (\(codeLabel(code))). Close Vial or any WebHID configurator tab that is using miniX, then reconnect."
        case .unsupportedTelemetry(let length):
            return "Received an unsupported \(length)-byte telemetry report. Update the miniX firmware or this app so both sides use the same protocol."
        }
    }
}

public enum CollectorStatus: Equatable, Sendable {
    case stopped
    case waiting(CollectorWaitingReason)
    case connected(String)
    case issue(CollectorIssue)

    public var title: String {
        switch self {
        case .stopped:
            return "Paused"
        case .waiting(.initial):
            return "Waiting for keyboard"
        case .waiting(.disconnected):
            return "Keyboard disconnected"
        case .connected(let name):
            return name
        case .issue(let issue):
            return issue.title
        }
    }

    public var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    public var detail: String? {
        switch self {
        case .stopped:
            return "Logging is paused. Resume to listen for miniX key events."
        case .waiting(.initial):
            return "Connect miniX. If it does not appear, close Vial or any WebHID keyboard tab first."
        case .waiting(.disconnected):
            return "Reconnect miniX to resume logging."
        case .connected:
            return "Recording physical key telemetry locally without accessibility permissions."
        case .issue(let issue):
            return issue.detail
        }
    }

    public var showsIssue: Bool {
        if case .issue = self {
            return true
        }
        return false
    }
}

public final class TelemetryCollector: @unchecked Sendable {
    private let queue = DispatchQueue(label: "minix-insight.hid")
    private let configuration: AppConfiguration
    private let onEvent: @Sendable (TelemetryEvent) -> Void
    private let onStatus: @Sendable (CollectorStatus) -> Void

    private var manager: IOHIDManager?
    private var devices: Set<IOHIDDevice> = []
    private var buffers: [IOHIDDevice: UnsafeMutablePointer<UInt8>] = [:]
    private var currentStatus: CollectorStatus = .stopped
    private var running = false

    public init(
        configuration: AppConfiguration = .miniX,
        onEvent: @escaping @Sendable (TelemetryEvent) -> Void,
        onStatus: @escaping @Sendable (CollectorStatus) -> Void
    ) {
        self.configuration = configuration
        self.onEvent = onEvent
        self.onStatus = onStatus
    }

    public func start() {
        queue.async {
            guard !self.running else { return }
            self.running = true
            self.setupManager()
        }
    }

    public func stop() {
        queue.async {
            self.running = false
            self.teardownManager()
            self.emitStatus(.stopped)
        }
    }

    private func setupManager() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let matches: [[String: Any]] = [configuration.deviceMatch.hidDictionary]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovedCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            emitStatus(.issue(.managerOpenFailed(code: Int32(result))))
            return
        }

        emitStatus(.waiting(.initial))
    }

    private func teardownManager() {
        for device in devices {
            unregister(device)
        }
        devices.removeAll()

        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }

    fileprivate func deviceMatched(_ device: IOHIDDevice) {
        queue.async {
            guard self.running, !self.devices.contains(device) else {
                return
            }

            let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard result == kIOReturnSuccess else {
                self.emitStatus(.issue(.deviceOpenFailed(code: Int32(result))))
                return
            }

            self.devices.insert(device)
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: TelemetryPacket.reportSize + 1)
            buffer.initialize(repeating: 0, count: TelemetryPacket.reportSize + 1)
            self.buffers[device] = buffer

            let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            IOHIDDeviceRegisterInputReportCallback(
                device,
                buffer,
                TelemetryPacket.reportSize + 1,
                inputReportCallback,
                context
            )
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

            self.emitStatus(.connected(self.deviceName(device)))
        }
    }

    fileprivate func deviceRemoved(_ device: IOHIDDevice) {
        queue.async {
            self.unregister(device)
            self.devices.remove(device)
            self.emitStatus(self.devices.isEmpty ? .waiting(.disconnected) : .connected(self.connectedDeviceName()))
        }
    }

    fileprivate func inputReport(device: IOHIDDevice, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        queue.async {
            guard self.running else { return }
            guard let event = TelemetryPacket.parse(bytes) else {
                self.emitStatus(.issue(.unsupportedTelemetry(length: length)))
                return
            }

            if !self.currentStatus.isConnected {
                self.emitStatus(.connected(self.deviceName(device)))
            }

            self.onEvent(event)
        }
    }

    private func unregister(_ device: IOHIDDevice) {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if let buffer = buffers.removeValue(forKey: device) {
            buffer.deinitialize(count: TelemetryPacket.reportSize + 1)
            buffer.deallocate()
        }
    }

    private func deviceName(_ device: IOHIDDevice) -> String {
        if let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String {
            return product
        }
        return configuration.deviceName
    }

    private func connectedDeviceName() -> String {
        guard let device = devices.first else {
            return configuration.deviceName
        }
        return deviceName(device)
    }

    private func emitStatus(_ status: CollectorStatus) {
        guard status != currentStatus else { return }
        currentStatus = status
        let onStatus = onStatus
        DispatchQueue.main.async {
            onStatus(status)
        }
    }
}

private func codeLabel(_ code: Int32) -> String {
    let bits = UInt32(bitPattern: code)
    return String(format: "0x%08x", bits)
}

private func deviceMatchedCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard result == kIOReturnSuccess, let context else { return }
    Unmanaged<TelemetryCollector>.fromOpaque(context).takeUnretainedValue().deviceMatched(device)
}

private func deviceRemovedCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard result == kIOReturnSuccess, let context else { return }
    Unmanaged<TelemetryCollector>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
}

private func inputReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard result == kIOReturnSuccess, let context, let sender else { return }
    let device = unsafeBitCast(sender, to: IOHIDDevice.self)
    Unmanaged<TelemetryCollector>.fromOpaque(context).takeUnretainedValue().inputReport(
        device: device,
        report: report,
        length: reportLength
    )
}
