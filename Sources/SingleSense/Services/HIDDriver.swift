import Foundation
import IOKit
import IOKit.hid
import QuartzCore

/// Everything the input report carries that the GameController framework does
/// not surface: real battery capacity, the mute button, the Edge paddles and
/// the second touch point.
public struct DSInputSnapshot: Equatable {
    public var batteryLevel: Float = 1.0
    public var isCharging: Bool = false
    public var micMuted: Bool = false
    public var micMuteButton: Bool = false
    public var touchpadButton: Bool = false
    public var touch1Active: Bool = false
    public var touch1X: Float = 0.5
    public var touch1Y: Float = 0.5
    public var touch2Active: Bool = false
    public var touch2X: Float = 0.5
    public var touch2Y: Float = 0.5
    public var edgeLeftPaddle: Bool = false
    public var edgeRightPaddle: Bool = false
    public var edgeFN1: Bool = false
    public var edgeFN2: Bool = false

    /// Angular rate in degrees per second, factory-calibrated.
    public var gyroPitch: Float = 0
    public var gyroYaw: Float = 0
    public var gyroRoll: Float = 0
    /// Proper acceleration in g, factory-calibrated.
    public var accelX: Float = 0
    public var accelY: Float = 0
    public var accelZ: Float = 0

    /// True when something happened that the UI must not miss — as opposed to
    /// telemetry that merely drifted since the last sample.
    func isDiscretelyDifferent(from other: DSInputSnapshot) -> Bool {
        micMuteButton != other.micMuteButton
            || touchpadButton != other.touchpadButton
            || touch1Active != other.touch1Active
            || touch2Active != other.touch2Active
            || edgeLeftPaddle != other.edgeLeftPaddle
            || edgeRightPaddle != other.edgeRightPaddle
            || edgeFN1 != other.edgeFN1
            || edgeFN2 != other.edgeFN2
            || micMuted != other.micMuted
            || isCharging != other.isCharging
            || batteryLevel != other.batteryLevel
    }
}

public final class HIDDriver {
    public static let shared = HIDDriver()

    public static let sonyVendorID = 0x054C
    public static let dualSenseProductID = 0x0CE6
    public static let dualSenseEdgeProductID = 0x0DF2

    /// Immutable snapshot of the attached device, published as a single value so
    /// the send path never observes a half-updated transport/layout pair.
    private struct DeviceContext {
        let device: IOHIDDevice
        let layout: DSOutputLayout
        let isBluetooth: Bool
        let isEdge: Bool
        /// Firmware at or past update version 2.21 takes the v2 rumble path.
        let useVibrationV2: Bool
        let calibration: DSIMUCalibration
    }

    private var hidManager: IOHIDManager?

    /// Guards every mutable field below. Device attach/removal runs on the run
    /// loop while sends run on `sendQueue`, so none of this is single-threaded.
    private let lock = NSLock()
    private var context: DeviceContext?
    private var outputSequence: UInt8 = 0
    private var deduplicator = DSSendDeduplicator()
    private var consecutiveFailures = 0
    private var linkHealth: LinkHealth = .healthy

    /// Ordering and backpressure for everything this driver sends.
    private var outputQueue = DSOutputQueue()

    /// State updates superseded before reaching the device; a rising count
    /// means the link is saturated.
    public var coalescedStateUpdates: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return outputQueue.coalescedStateUpdates
    }

    /// A congested Bluetooth link can refuse a report; give up after this many
    /// tries so a vanished device cannot spin the send queue forever.
    private static let maxSendAttempts = 5

    /// IOKit writes incoming reports straight into this buffer, so it has to
    /// outlive the callback registration.
    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private var lastSnapshot = DSInputSnapshot()
    private var lastSnapshotDelivery: TimeInterval = 0
    /// Continuous telemetry is published at 60 Hz; the UI cannot use more.
    private static let snapshotInterval: TimeInterval = 1.0 / 60.0

    public var onDeviceConnected: ((_ isEdge: Bool, _ isBT: Bool) -> Void)?
    public var onDeviceDisconnected: (() -> Void)?
    public var onInputSnapshot: ((DSInputSnapshot) -> Void)?
    /// Fired on the I/O thread for every input report, unthrottled, so cursor
    /// motion tracks at the controller's full report rate instead of the UI's.
    public var onTouchpadSample: ((DSInputSnapshot) -> Void)?
    /// Reports how well writes are landing, so the UI can say so instead of
    /// the failure only reaching the console.
    public var onLinkHealthChanged: ((LinkHealth) -> Void)?

    private let sendQueue = DispatchQueue(label: "com.singlesense.hid.send", qos: .userInteractive)

    /// IOKit delivers device and input-report callbacks on whichever run loop
    /// the manager is scheduled on. The DualSense reports hundreds of times a
    /// second, so that run loop is a dedicated thread rather than the main one
    /// — otherwise every packet competes with SwiftUI for the main thread.
    private var ioThread: Thread?
    private var ioRunLoop: CFRunLoop?

    /// True while an output report can actually reach the hardware. The
    /// GameController fallbacks in `DualSenseManager` key off this.
    public var isDeviceOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return context != nil
    }

    private init() {}

    // MARK: - Lifecycle

    public func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = manager

        let matchingCriteria: [[String: Any]] = [
            [kIOHIDVendorIDKey: HIDDriver.sonyVendorID, kIOHIDProductIDKey: HIDDriver.dualSenseProductID],
            [kIOHIDVendorIDKey: HIDDriver.sonyVendorID, kIOHIDProductIDKey: HIDDriver.dualSenseEdgeProductID]
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingCriteria as CFArray)

        let matchCallback: IOHIDDeviceCallback = { context, _, _, device in
            guard let context = context else { return }
            Unmanaged<HIDDriver>.fromOpaque(context).takeUnretainedValue()
                .handleDeviceAttached(device: device)
        }

        let removeCallback: IOHIDDeviceCallback = { context, _, _, device in
            guard let context = context else { return }
            Unmanaged<HIDDriver>.fromOpaque(context).takeUnretainedValue()
                .handleDeviceRemoved(device: device)
        }

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceMatchingCallback(manager, matchCallback, selfPointer)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, removeCallback, selfPointer)

        startIOThread(with: manager)
    }

    /// Spins up the run loop that owns every IOKit callback for this driver.
    private func startIOThread(with manager: IOHIDManager) {
        let ready = DispatchSemaphore(value: 0)

        let thread = Thread { [weak self] in
            guard let self = self else { ready.signal(); return }
            guard let runLoop: CFRunLoop = CFRunLoopGetCurrent() else { ready.signal(); return }
            self.ioRunLoop = runLoop

            IOHIDManagerScheduleWithRunLoop(manager, runLoop, CFRunLoopMode.commonModes.rawValue)
            let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            if openStatus != kIOReturnSuccess {
                print("[SingleSense HID] IOHIDManagerOpen failed: \(self.hexStatus(openStatus))")
            }

            // A run loop with no sources returns immediately; the manager
            // installs one, but keep an explicit port so stop() always has a
            // live run loop to signal.
            let keepAlive = CFRunLoopSourceContext()
            var context = keepAlive
            if let source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) {
                CFRunLoopAddSource(runLoop, source, .commonModes)
            }

            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "com.singlesense.hid.io"
        thread.qualityOfService = .userInteractive
        self.ioThread = thread
        thread.start()

        // Callers may attach a device immediately after start(); make sure the
        // run loop exists before returning.
        _ = ready.wait(timeout: .now() + 2.0)
    }

    public func stop() {
        lock.lock()
        let device = context?.device
        context = nil
        deduplicator.invalidate()
        let buffer = inputBuffer
        inputBuffer = nil
        lock.unlock()

        if let device = device {
            HIDDriver.detach(device: device, buffer: buffer)
        } else {
            buffer?.deallocate()
        }

        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            if let runLoop = ioRunLoop {
                IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.commonModes.rawValue)
            }
            self.hidManager = nil
        }

        if let runLoop = ioRunLoop {
            CFRunLoopStop(runLoop)
        }
        ioRunLoop = nil
        ioThread = nil
    }

    // MARK: - Device attach / detach

    /// Tears a device down in the only safe order: drop the input callback
    /// first, then close, and only then free the buffer IOKit was writing into.
    private static func detach(device: IOHIDDevice, buffer: UnsafeMutablePointer<UInt8>?) {
        if let buffer = buffer {
            IOHIDDeviceRegisterInputReportCallback(
                device, buffer, CFIndex(DualSenseProtocol.inputReportSizeBT), nil, nil
            )
        }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer?.deallocate()
    }

    private func handleDeviceAttached(device: IOHIDDevice) {
        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            // Without an open handle every SetReport would fail silently, so
            // there is nothing to gain by keeping the device around.
            print("[SingleSense HID] IOHIDDeviceOpen failed: \(hexStatus(openResult)) — device ignored")
            return
        }

        let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue
            ?? HIDDriver.dualSenseProductID
        let isEdge = (productID == HIDDriver.dualSenseEdgeProductID)

        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
        let maxOutputSize = (IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 0
        let isBluetooth = (transport?.lowercased().contains("bluetooth") == true)
            || maxOutputSize >= DualSenseProtocol.outputReportSizeBT

        let layout = isBluetooth ? DSOutputLayout.bluetooth : DSOutputLayout.usb
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: DualSenseProtocol.inputReportSizeBT)
        buffer.initialize(repeating: 0, count: DualSenseProtocol.inputReportSizeBT)

        lock.lock()
        let staleDevice = context?.device
        let staleBuffer = inputBuffer
        // Start on the conservative v1 rumble path; the firmware probe below
        // upgrades it once it knows better.
        context = DeviceContext(
            device: device,
            layout: layout,
            isBluetooth: isBluetooth,
            isEdge: isEdge,
            useVibrationV2: false,
            calibration: .identity
        )
        outputSequence = 0
        consecutiveFailures = 0
        linkHealth = .healthy
        deduplicator.invalidate()
        inputBuffer = buffer
        lastSnapshot = DSInputSnapshot()
        lock.unlock()
        if let staleDevice = staleDevice {
            HIDDriver.detach(device: staleDevice, buffer: staleBuffer)
        } else {
            staleBuffer?.deallocate()
        }

        let inputCallback: IOHIDReportCallback = { context, _, _, _, reportID, report, reportLength in
            guard let context = context else { return }
            Unmanaged<HIDDriver>.fromOpaque(context).takeUnretainedValue()
                .handleInputReport(reportID: reportID, report: report, length: reportLength)
        }
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            CFIndex(DualSenseProtocol.inputReportSizeBT),
            inputCallback,
            selfPointer
        )

        print("""
            [SingleSense HID] Attached \(isEdge ? "DualSense Edge" : "DualSense") over \
            \(isBluetooth ? "Bluetooth" : "USB") — output report \(layout.totalSize) bytes
            """)

        // Release the startup animation before anything tries to program the
        // lightbar or the player indicator row.
        sendLEDReset()

        // A feature report is a blocking round trip to the controller, so it
        // stays off the run loop that IOKit delivers device events on.
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            let version = self.readUpdateVersion(device: device, isBluetooth: isBluetooth)
            let useV2 = version >= DualSenseProtocol.vibrationV2MinimumVersion
            let calibration = self.readCalibration(device: device, isBluetooth: isBluetooth)

            self.lock.lock()
            if let current = self.context, current.device == device {
                self.context = DeviceContext(
                    device: current.device,
                    layout: current.layout,
                    isBluetooth: current.isBluetooth,
                    isEdge: current.isEdge,
                    useVibrationV2: useV2,
                    calibration: calibration
                )
                // The next report must go out even if it is byte-identical,
                // because the rumble flags just changed underneath it.
                self.deduplicator.invalidate()
            }
            self.lock.unlock()

            print("[SingleSense HID] Update version \(version >> 8).\(version & 0xFF), rumble path \(useV2 ? "v2" : "v1")")
        }

        DispatchQueue.main.async { [weak self] in
            self?.onDeviceConnected?(isEdge, isBluetooth)
        }
    }

    private func handleDeviceRemoved(device: IOHIDDevice) {
        lock.lock()
        guard let current = context, current.device == device else {
            lock.unlock()
            return
        }
        context = nil
        deduplicator.invalidate()
        let buffer = inputBuffer
        inputBuffer = nil
        lock.unlock()

        HIDDriver.detach(device: device, buffer: buffer)

        print("[SingleSense HID] Controller removed")
        DispatchQueue.main.async { [weak self] in
            self?.onDeviceDisconnected?()
        }
    }

    /// Fetches one feature report, verifying its Bluetooth CRC.
    /// Returns nil when the device refuses or the reply is malformed.
    private func readFeatureReport(
        _ reportID: UInt8,
        size: Int,
        device: IOHIDDevice,
        isBluetooth: Bool
    ) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: size)
        buffer[0] = reportID
        var length = CFIndex(size)

        let result = IOHIDDeviceGetReport(
            device, kIOHIDReportTypeFeature, CFIndex(reportID), &buffer, &length
        )
        guard result == kIOReturnSuccess, length > 4, buffer[0] == reportID else { return nil }

        if isBluetooth {
            let crcOffset = Int(length) - 4
            let expected = UInt32(buffer[crcOffset])
                | (UInt32(buffer[crcOffset + 1]) << 8)
                | (UInt32(buffer[crcOffset + 2]) << 16)
                | (UInt32(buffer[crcOffset + 3]) << 24)
            let actual = DualSenseChecksum.computeCRC32(
                for: Array(buffer[0..<crcOffset]),
                prefix: DualSenseChecksum.featureSeed
            )
            guard expected == actual else { return nil }
        }

        return Array(buffer[0..<Int(length)])
    }

    /// Reads feature report 0x20 to learn the controller's update version.
    /// Mirrors `dualsense_get_firmware_info`; failure is non-fatal and just
    /// leaves the driver on the conservative v1 rumble path.
    private func readUpdateVersion(device: IOHIDDevice, isBluetooth: Bool) -> UInt16 {
        guard let buffer = readFeatureReport(
            DualSenseProtocol.featureReportFirmwareInfo,
            size: DualSenseProtocol.featureReportFirmwareInfoSize,
            device: device,
            isBluetooth: isBluetooth
        ), buffer.count >= 46 else { return 0 }

        // update_version lives at buf[44] as a little-endian u16.
        return UInt16(buffer[44]) | (UInt16(buffer[45]) << 8)
    }

    /// Reads feature report 0x05, the factory IMU calibration.
    private func readCalibration(device: IOHIDDevice, isBluetooth: Bool) -> DSIMUCalibration {
        guard let buffer = readFeatureReport(
            DualSenseProtocol.featureReportCalibration,
            size: DualSenseProtocol.featureReportCalibrationSize,
            device: device,
            isBluetooth: isBluetooth
        ), let calibration = DSIMUCalibration.parse(featureReport: buffer) else {
            print("[SingleSense HID] IMU calibration unavailable — using raw scaling")
            return .identity
        }
        return calibration
    }

    // MARK: - Output

    /// Builds a complete output report except for the Bluetooth sequence number
    /// and CRC32, which are stamped at send time.
    ///
    /// Pure and layout-driven so the wire format can be verified without
    /// hardware attached.
    static func buildOutputReport(
        layout: DSOutputLayout,
        useVibrationV2: Bool,
        lightbar: RGBColor,
        playerLEDMask: UInt8,
        playerBrightness: PlayerLEDBrightness,
        micLED: MicLEDMode,
        leftMotor: UInt8,
        rightMotor: UInt8,
        leftTrigger: SingleTriggerConfig,
        rightTrigger: SingleTriggerConfig
    ) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: layout.totalSize)
        report[0] = layout.reportID
        if layout.hasCRC {
            // seq_tag is stamped at send time; tag is a fixed magic value
            // the firmware requires ("Tag must be set" in the kernel).
            report[layout.tag] = DualSenseProtocol.outputTag
        }

        // Enable exactly the subsystems being driven — and no more. Bits 5-7
        // of valid_flag0 would switch on the audio control block, whose volume
        // bytes are zero here, muting the controller's speaker and mic.
        //
        // The two trigger bits are not optional: without them the firmware
        // discards the effect blocks below however well-formed they are.
        var validFlag0 = DualSenseProtocol.ValidFlag0.hapticsSelect
            | DualSenseProtocol.ValidFlag0.rightTriggerMotorEnable
            | DualSenseProtocol.ValidFlag0.leftTriggerMotorEnable
        var validFlag2 = DualSenseProtocol.ValidFlag2.ledBrightnessControlEnable
        if useVibrationV2 {
            validFlag2 |= DualSenseProtocol.ValidFlag2.compatibleVibration2
        } else {
            validFlag0 |= DualSenseProtocol.ValidFlag0.compatibleVibration
        }

        let validFlag1 = DualSenseProtocol.ValidFlag1.micMuteLEDControlEnable
            | DualSenseProtocol.ValidFlag1.lightbarControlEnable
            | DualSenseProtocol.ValidFlag1.playerIndicatorControlEnable

        report[layout.validFlag0] = validFlag0
        report[layout.validFlag1] = validFlag1
        report[layout.validFlag2] = validFlag2

        report[layout.motorRight] = rightMotor
        report[layout.motorLeft] = leftMotor

        report[layout.muteButtonLED] = micLED.rawValueByte

        rightTrigger.encode(into: &report, at: layout.rightTriggerEffect)
        leftTrigger.encode(into: &report, at: layout.leftTriggerEffect)

        // 0x00 keeps the lightbar in steady output; bit 1 would fade it out.
        report[layout.lightbarSetup] = 0x00
        report[layout.ledBrightness] = playerBrightness.rawValueByte
        report[layout.playerLEDs] = playerBrightness.extinguishesLEDs
            ? 0x00
            : (playerLEDMask | DualSenseProtocol.playerLEDInstant)
        report[layout.lightbarRed] = lightbar.redByte
        report[layout.lightbarGreen] = lightbar.greenByte
        report[layout.lightbarBlue] = lightbar.blueByte

        return report
    }

    /// Builds the one-shot report that hands lightbar and player-LED control
    /// over to the host.
    ///
    /// Mirrors `dualsense_reset_leds`: it carries nothing but the lightbar
    /// setup command, because over Bluetooth the controller runs a startup
    /// animation and holds its own colour until this is sent — any LED
    /// programming before it is simply ignored.
    static func buildLEDResetReport(layout: DSOutputLayout) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: layout.totalSize)
        report[0] = layout.reportID
        if layout.hasCRC {
            report[layout.tag] = DualSenseProtocol.outputTag
        }
        report[layout.validFlag2] = DualSenseProtocol.ValidFlag2.lightbarSetupControlEnable
        report[layout.lightbarSetup] = DualSenseProtocol.LightbarSetup.lightOut
        return report
    }

    /// Releases the controller's startup LED animation. Must land before the
    /// first lightbar or player-LED report or those have no effect.
    public func sendLEDReset() {
        lock.lock()
        let needsDrain = outputQueue.enqueue(.ledReset)
        lock.unlock()
        if needsDrain { scheduleDrain() }
    }

    /// Hands one drain pass to the send queue. Only ever one is outstanding.
    private func scheduleDrain() {
        sendQueue.async { [weak self] in
            self?.drainOutput()
        }
    }

    private func drainOutput() {
        while true {
            lock.lock()
            guard let device = context else {
                outputQueue.clear()
                lock.unlock()
                return
            }
            guard let batch = outputQueue.takeWork() else {
                lock.unlock()
                return
            }
            lock.unlock()

            for event in batch.events {
                switch event {
                case .ledReset:
                    var report = HIDDriver.buildLEDResetReport(layout: device.layout)
                    transmit(&report, layout: device.layout, device: device.device)
                }
            }

            if let state = batch.state, !send(state, device: device) {
                guard state.attempts < Self.maxSendAttempts else { continue }

                lock.lock()
                outputQueue.requeue(state)
                lock.unlock()

                // Back off rather than spinning on a busy link, and leave the
                // drain claimed so nothing else queues one.
                sendQueue.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                    self?.drainOutput()
                }
                return
            }
        }
    }

    /// Stamps the Bluetooth sequence number and CRC, then hands the report to
    /// IOKit. Must be called on `sendQueue`.
    @discardableResult
    private func transmit(_ report: inout [UInt8], layout: DSOutputLayout, device: IOHIDDevice) -> Bool {
        if layout.hasCRC {
            lock.lock()
            report[layout.sequenceTag] = (outputSequence << 4)
            outputSequence = (outputSequence + 1) & 0x0F
            lock.unlock()
            DualSenseChecksum.appendBluetoothCRC(to: &report)
        }

        let status = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(layout.reportID),
            report,
            report.count
        )

        guard status == kIOReturnSuccess else {
            print("[SingleSense HID] SetReport failed: \(hexStatus(status))")
            recordSendOutcome(delivered: false)
            return false
        }
        recordSendOutcome(delivered: true)
        return true
    }

    /// Collapses a run of write results into a health level. One refusal is
    /// ordinary congestion; exhausting the retries means nothing is landing.
    private func recordSendOutcome(delivered: Bool) {
        lock.lock()
        if delivered {
            consecutiveFailures = 0
        } else {
            consecutiveFailures += 1
        }
        let health: LinkHealth
        switch consecutiveFailures {
        case 0: health = .healthy
        case ..<Self.maxSendAttempts: health = .congested
        default: health = .unresponsive
        }
        let changed = health != linkHealth
        if changed { linkHealth = health }
        lock.unlock()

        guard changed else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onLinkHealthChanged?(health)
        }
    }

    /// Builds and sends a full output report.
    public func sendHardwareState(
        lightbar: RGBColor,
        playerLEDMask: UInt8,
        playerBrightness: PlayerLEDBrightness,
        micLED: MicLEDMode,
        leftMotor: UInt8,
        rightMotor: UInt8,
        leftTrigger: SingleTriggerConfig,
        rightTrigger: SingleTriggerConfig,
        forceSend: Bool = false
    ) {
        let state = DSHardwareState(
            lightbar: lightbar,
            playerLEDMask: playerLEDMask,
            playerBrightness: playerBrightness,
            micLED: micLED,
            leftMotor: leftMotor,
            rightMotor: rightMotor,
            leftTrigger: leftTrigger,
            rightTrigger: rightTrigger,
            forceSend: forceSend
        )

        lock.lock()
        let needsDrain = outputQueue.enqueue(state)
        lock.unlock()

        if needsDrain { scheduleDrain() }
    }

    /// Renders one hardware state onto the wire. Runs on `sendQueue`.
    /// Returns false when the report did not reach the device.
    private func send(_ state: DSHardwareState, device: DeviceContext) -> Bool {
        let layout = device.layout
        var report = HIDDriver.buildOutputReport(
            layout: layout,
            useVibrationV2: device.useVibrationV2,
            lightbar: state.lightbar,
            playerLEDMask: state.playerLEDMask,
            playerBrightness: state.playerBrightness,
            micLED: state.micLED,
            leftMotor: state.leftMotor,
            rightMotor: state.rightMotor,
            leftTrigger: state.leftTrigger,
            rightTrigger: state.rightTrigger
        )

        // Deduplicate before the sequence number and CRC go in, otherwise
        // every report would differ and the filter would never hit.
        let now = Date()
        lock.lock()
        let wanted = deduplicator.shouldSend(report, forced: state.forceSend, now: now)
        lock.unlock()
        guard wanted else { return true }

        let candidate = report
        let delivered = transmit(&report, layout: layout, device: device.device)

        lock.lock()
        if delivered {
            deduplicator.commit(candidate, at: now)
        } else {
            deduplicator.invalidate()
        }
        lock.unlock()

        return delivered
    }


    // MARK: - Input

    private func handleInputReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        lock.lock()
        let isBluetooth = context?.isBluetooth ?? false
        let isEdge = context?.isEdge ?? false
        let calibration = context?.calibration ?? .identity
        lock.unlock()

        let size = Int(length)
        guard size > 0 else { return }
        let data = UnsafeBufferPointer(start: report, count: size)

        // macOS delivers numbered reports with the report ID at byte 0, but be
        // tolerant of a buffer that already had it stripped.
        let expectedID = isBluetooth ? DualSenseProtocol.inputReportIDBT : DualSenseProtocol.inputReportIDUSB
        var base = DSInputLayout.payloadOffset(isBluetooth: isBluetooth)
        if data[0] != expectedID {
            guard UInt8(reportID) == expectedID else { return }
            base -= 1
        }
        guard base >= 0, base + DSInputLayout.size <= size else { return }

        if isBluetooth {
            // Bluetooth input reports carry a CRC32 over everything before it.
            guard size >= 4 else { return }
            let crcOffset = size - 4
            let expected = UInt32(data[crcOffset])
                | (UInt32(data[crcOffset + 1]) << 8)
                | (UInt32(data[crcOffset + 2]) << 16)
                | (UInt32(data[crcOffset + 3]) << 24)
            let actual = DualSenseChecksum.computeCRC32(
                for: data,
                count: crcOffset,
                prefix: DualSenseChecksum.inputSeed
            )
            guard expected == actual else { return }
        }

        var snapshot = DSInputSnapshot()

        let buttons2 = data[base + DSInputLayout.buttons + 2]
        snapshot.micMuteButton = (buttons2 & DualSenseProtocol.Buttons2.micMute) != 0
        snapshot.touchpadButton = (buttons2 & DualSenseProtocol.Buttons2.touchpad) != 0
        if isEdge {
            snapshot.edgeFN1 = (buttons2 & DualSenseProtocol.Buttons2.edgeFN1) != 0
            snapshot.edgeFN2 = (buttons2 & DualSenseProtocol.Buttons2.edgeFN2) != 0
            snapshot.edgeLeftPaddle = (buttons2 & DualSenseProtocol.Buttons2.edgeLeftPaddle) != 0
            snapshot.edgeRightPaddle = (buttons2 & DualSenseProtocol.Buttons2.edgeRightPaddle) != 0
        }

        let point1 = decodeTouchPoint(data, at: base + DSInputLayout.touchPoints)
        snapshot.touch1Active = point1.active
        snapshot.touch1X = point1.x
        snapshot.touch1Y = point1.y

        let point2 = decodeTouchPoint(data, at: base + DSInputLayout.touchPoints + 4)
        snapshot.touch2Active = point2.active
        snapshot.touch2X = point2.x
        snapshot.touch2Y = point2.y

        // Gyro and accelerometer are signed 16-bit, little-endian. The gyro
        // axes arrive as pitch, yaw, roll.
        func axis(_ offset: Int, _ index: Int) -> Int {
            let lo = UInt16(data[offset + index * 2])
            let hi = UInt16(data[offset + index * 2 + 1]) << 8
            return Int(Int16(bitPattern: lo | hi))
        }

        let gyroBase = base + DSInputLayout.gyro
        let accelBase = base + DSInputLayout.accel
        let gyroScale = DualSenseProtocol.gyroResolutionPerDegPerSec
        let accelScale = DualSenseProtocol.accelResolutionPerG

        snapshot.gyroPitch = Float(calibration.gyro[0].apply(axis(gyroBase, 0))) / gyroScale
        snapshot.gyroYaw = Float(calibration.gyro[1].apply(axis(gyroBase, 1))) / gyroScale
        snapshot.gyroRoll = Float(calibration.gyro[2].apply(axis(gyroBase, 2))) / gyroScale
        snapshot.accelX = Float(calibration.accel[0].apply(axis(accelBase, 0))) / accelScale
        snapshot.accelY = Float(calibration.accel[1].apply(axis(accelBase, 1))) / accelScale
        snapshot.accelZ = Float(calibration.accel[2].apply(axis(accelBase, 2))) / accelScale

        let status0 = data[base + DSInputLayout.status]
        let status1 = data[base + DSInputLayout.status + 1]
        snapshot.micMuted = (status1 & DualSenseProtocol.Status1.micMute) != 0

        // status[0] packs capacity in the low nibble and charge state in the high
        // nibble, exactly as `dualsense_parse_report` decodes it.
        let capacityUnits = Int(status0 & 0x0F)
        switch (status0 >> 4) & 0x0F {
        case 0x0:
            snapshot.batteryLevel = Float(min(capacityUnits * 10 + 5, 100)) / 100
            snapshot.isCharging = false
        case 0x1:
            snapshot.batteryLevel = Float(min(capacityUnits * 10 + 5, 100)) / 100
            snapshot.isCharging = true
        case 0x2:
            snapshot.batteryLevel = 1.0
            snapshot.isCharging = true
        default:
            // 0xa/0xb are temperature or voltage faults, 0xf a charging error.
            snapshot.batteryLevel = 0
            snapshot.isCharging = false
        }

        // The trackpad runs here, on the I/O thread: every report matters for
        // smooth motion, and hopping to main would both add latency and flood
        // the main queue at the controller's report rate.
        onTouchpadSample?(snapshot)

        // The IMU moves every report, so a plain "did anything change" test
        // would push ~250 updates a second at SwiftUI. Continuous fields are
        // rate-limited; buttons, battery and charge state still go straight
        // through, because dropping one of those loses an event rather than a
        // frame.
        let now = CACurrentMediaTime()
        lock.lock()
        let discreteChanged = snapshot.isDiscretelyDifferent(from: lastSnapshot)
        let due = now - lastSnapshotDelivery >= Self.snapshotInterval
        let deliver = discreteChanged || (due && snapshot != lastSnapshot)
        if deliver {
            lastSnapshot = snapshot
            lastSnapshotDelivery = now
        }
        lock.unlock()
        guard deliver else { return }

        DispatchQueue.main.async { [weak self] in
            self?.onInputSnapshot?(snapshot)
        }
    }

    /// `struct dualsense_touch_point`: contact byte, then 12-bit X and Y split
    /// across three bytes. Bit 7 of the contact byte marks the point inactive.
    private func decodeTouchPoint(
        _ data: UnsafeBufferPointer<UInt8>,
        at offset: Int
    ) -> (active: Bool, x: Float, y: Float) {
        let contact = data[offset]
        let xLow = data[offset + 1]
        let packed = data[offset + 2]
        let yHigh = data[offset + 3]

        let x = (Int(packed & 0x0F) << 8) | Int(xLow)
        let y = (Int(yHigh) << 4) | Int((packed >> 4) & 0x0F)

        return (
            active: (contact & 0x80) == 0,
            x: min(max(Float(x) / DualSenseProtocol.touchpadWidth, 0), 1),
            y: min(max(Float(y) / DualSenseProtocol.touchpadHeight, 0), 1)
        )
    }

    private func hexStatus(_ status: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: status))
    }
}
