import Foundation
@preconcurrency import IOKit.hid

public enum CollectorStatus: Equatable, Sendable {
    case stopped
    case waiting
    case connected(String)
    case error(String)

    public var title: String {
        switch self {
        case .stopped:
            return "Paused"
        case .waiting:
            return "Waiting"
        case .connected:
            return "Connected"
        case .error:
            return "Error"
        }
    }

    public var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

public final class TelemetryCollector: @unchecked Sendable {
    private let queue = DispatchQueue(label: "minix-insight.hid")
    private let onEvent: @Sendable (TelemetryEvent) -> Void
    private let onStatus: @Sendable (CollectorStatus) -> Void

    private var manager: IOHIDManager?
    private var devices: Set<IOHIDDevice> = []
    private var buffers: [IOHIDDevice: UnsafeMutablePointer<UInt8>] = [:]
    private var running = false

    public init(onEvent: @escaping @Sendable (TelemetryEvent) -> Void, onStatus: @escaping @Sendable (CollectorStatus) -> Void) {
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

        let matches: [[String: Any]] = [
            [
                kIOHIDVendorIDKey as String: 0x5262,
                kIOHIDProductIDKey as String: 0x4E4B,
                kIOHIDDeviceUsagePageKey as String: 0xFF60,
                kIOHIDDeviceUsageKey as String: 0x61,
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovedCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            emitStatus(.error("Cannot open Raw HID manager"))
            return
        }

        emitStatus(.waiting)
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
                self.emitStatus(.error("Cannot open keyboard Raw HID interface"))
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
            self.emitStatus(self.devices.isEmpty ? .waiting : .connected("miniX"))
        }
    }

    fileprivate func inputReport(device: IOHIDDevice, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        guard let event = TelemetryPacket.parse(bytes) else {
            return
        }
        onEvent(event)
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
        return "miniX"
    }

    private func emitStatus(_ status: CollectorStatus) {
        let onStatus = onStatus
        DispatchQueue.main.async {
            onStatus(status)
        }
    }
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
