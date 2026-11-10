import Foundation

/// Wire format for the DualSense HID protocol.
///
/// Report layouts follow `struct dualsense_output_report_common`,
/// `dualsense_output_report_bt` / `_usb` and `dualsense_input_report` in the
/// Linux kernel driver (`drivers/hid/hid-playstation.c`), which is the
/// authoritative reference for everything except the adaptive triggers.
///
/// Adaptive trigger effects are not implemented by the kernel; that encoding
/// follows the reverse-engineered `TriggerEffectGenerator` used by DualSenseX.
public enum DualSenseProtocol {

    // MARK: - Report identifiers and sizes

    public static let outputReportIDUSB: UInt8 = 0x02
    public static let outputReportIDBT: UInt8 = 0x31

    /// `DS_OUTPUT_REPORT_USB_SIZE`. Includes the leading report ID byte.
    public static let outputReportSizeUSB = 63
    /// `DS_OUTPUT_REPORT_BT_SIZE`. Includes the report ID byte and trailing CRC32.
    public static let outputReportSizeBT = 78

    public static let inputReportIDUSB: UInt8 = 0x01
    public static let inputReportIDBT: UInt8 = 0x31
    public static let inputReportSizeUSB = 64
    public static let inputReportSizeBT = 78

    public static let featureReportFirmwareInfo: UInt8 = 0x20
    public static let featureReportFirmwareInfoSize = 64

    /// `DS_OUTPUT_TAG`. The kernel notes this must be set; exact meaning unclear.
    public static let outputTag: UInt8 = 0x10

    /// Controllers at or past this update version take the v2 rumble path.
    /// Mirrors `ds->use_vibration_v2 = ds->update_version >= DS_FEATURE_VERSION(2, 21)`.
    public static let vibrationV2MinimumVersion: UInt16 = (2 << 8) | 21

    // MARK: - Output report flag bits

    /// Bits 2-4 are absent from the kernel's header because it implements no
    /// adaptive triggers and no headphone volume; the names come from
    /// dualsensectl, which does.
    public enum ValidFlag0 {
        public static let compatibleVibration: UInt8 = 1 << 0
        /// Makes the actuators follow the rumble bytes and ignore the USB
        /// audio channels 3-4 — SDL calls it "disable audio haptics". It has
        /// to be clear for anything played on those channels to be felt.
        public static let hapticsSelect: UInt8 = 1 << 1
        /// Without this the firmware ignores the right trigger effect block
        /// entirely, however well-formed it is.
        public static let rightTriggerMotorEnable: UInt8 = 1 << 2
        public static let leftTriggerMotorEnable: UInt8 = 1 << 3
        public static let headphoneVolumeEnable: UInt8 = 1 << 4
        public static let speakerVolumeEnable: UInt8 = 1 << 5
        public static let micVolumeEnable: UInt8 = 1 << 6
        public static let audioControlEnable: UInt8 = 1 << 7
    }

    public enum ValidFlag1 {
        public static let micMuteLEDControlEnable: UInt8 = 1 << 0
        public static let powerSaveControlEnable: UInt8 = 1 << 1
        public static let lightbarControlEnable: UInt8 = 1 << 2
        public static let releaseLEDs: UInt8 = 1 << 3
        public static let playerIndicatorControlEnable: UInt8 = 1 << 4
        public static let hapticLowPassFilterEnable: UInt8 = 1 << 5
        public static let vibrationAttenuationEnable: UInt8 = 1 << 6
        public static let audioControl2Enable: UInt8 = 1 << 7
    }

    /// Values for the `lightbar_setup` byte.
    public enum LightbarSetup {
        /// Explicitly turns the lightbar back on. Absent from the kernel;
        /// named by dualsensectl.
        public static let lightOn: UInt8 = 1 << 0
        /// `DS_OUTPUT_LIGHTBAR_SETUP_LIGHT_OUT`. Fades the boot animation out
        /// and hands lightbar and LED programming over to the host.
        public static let lightOut: UInt8 = 1 << 1
    }

    public enum ValidFlag2 {
        /// The `led_brightness` byte is ignored unless this is set.
        public static let ledBrightnessControlEnable: UInt8 = 1 << 0
        public static let lightbarSetupControlEnable: UInt8 = 1 << 1
        public static let compatibleVibration2: UInt8 = 1 << 2
    }

    /// Bit 5 of `player_leds` suppresses the slow fade-in, so a pattern change
    /// lands immediately instead of ramping.
    public static let playerLEDInstant: UInt8 = 1 << 5

    /// `DS_OUTPUT_AUDIO_FLAGS_OUTPUT_PATH_SEL`, bits 4-5 of `audio_control`.
    public static let audioOutputPathShift: UInt8 = 4
    /// `DS_OUTPUT_AUDIO_FLAGS2_SP_PREAMP_GAIN`, bits 0-2 of `audio_control2`.
    public static let speakerPreampGainMask: UInt8 = 0x07

    // MARK: - Input report bit masks

    public enum Buttons2 {
        public static let psHome: UInt8 = 1 << 0
        public static let touchpad: UInt8 = 1 << 1
        public static let micMute: UInt8 = 1 << 2
        /// DualSense Edge reuses the upper nibble of `buttons[2]`.
        public static let edgeFN1: UInt8 = 1 << 4
        public static let edgeFN2: UInt8 = 1 << 5
        public static let edgeLeftPaddle: UInt8 = 1 << 6
        public static let edgeRightPaddle: UInt8 = 1 << 7
    }

    public enum Status1 {
        public static let headphoneDetect: UInt8 = 1 << 0
        public static let micDetect: UInt8 = 1 << 1
        public static let micMute: UInt8 = 1 << 2
    }

    // MARK: - Hardware limits

    /// `DS_TOUCHPAD_WIDTH` / `DS_TOUCHPAD_HEIGHT`.
    public static let touchpadWidth: Float = 1920
    public static let touchpadHeight: Float = 1080
    /// `DS_ACC_RES_PER_G`, range +/- 4g.
    public static let accelResolutionPerG: Float = 8192
    /// `DS_GYRO_RES_PER_DEG_S`.
    public static let gyroResolutionPerDegPerSec: Float = 1024
    /// `DS_ACC_RANGE`, +/- 4g expressed in raw counts.
    public static let accelRange: Float = 4 * accelResolutionPerG
    /// `DS_GYRO_RANGE`.
    public static let gyroRange: Float = 2048 * gyroResolutionPerDegPerSec

    public static let featureReportCalibration: UInt8 = 0x05
    public static let featureReportCalibrationSize = 41
}

// MARK: - Output report layout

/// Byte offsets into a DualSense output report.
///
/// USB and Bluetooth share `struct dualsense_output_report_common`; they differ
/// only in how many header bytes precede it. Deriving every offset from
/// `commonBase` is what keeps the two transports from drifting apart.
public struct DSOutputLayout {
    public let reportID: UInt8
    public let totalSize: Int
    /// Index of the first byte of `dualsense_output_report_common`.
    public let commonBase: Int
    public let hasCRC: Bool

    /// USB: `[report_id][common][reserved * 15]`
    public static let usb = DSOutputLayout(
        reportID: DualSenseProtocol.outputReportIDUSB,
        totalSize: DualSenseProtocol.outputReportSizeUSB,
        commonBase: 1,
        hasCRC: false
    )

    /// Bluetooth: `[report_id][seq_tag][tag][common][reserved * 24][crc32]`
    public static let bluetooth = DSOutputLayout(
        reportID: DualSenseProtocol.outputReportIDBT,
        totalSize: DualSenseProtocol.outputReportSizeBT,
        commonBase: 3,
        hasCRC: true
    )

    // Bluetooth-only header bytes.
    public var sequenceTag: Int { 1 }
    public var tag: Int { 2 }

    // Offsets within `dualsense_output_report_common`.
    public var validFlag0: Int { commonBase + 0 }
    public var validFlag1: Int { commonBase + 1 }
    public var motorRight: Int { commonBase + 2 }
    public var motorLeft: Int { commonBase + 3 }
    public var headphoneVolume: Int { commonBase + 4 }
    public var speakerVolume: Int { commonBase + 5 }
    public var micVolume: Int { commonBase + 6 }
    public var audioControl: Int { commonBase + 7 }
    public var muteButtonLED: Int { commonBase + 8 }
    public var powerSaveControl: Int { commonBase + 9 }
    /// `reserved2[27]` starts here and carries both trigger effect blocks.
    public var rightTriggerEffect: Int { commonBase + 10 }
    public var leftTriggerEffect: Int { commonBase + 21 }
    public var audioControl2: Int { commonBase + 37 }
    public var validFlag2: Int { commonBase + 38 }
    public var lightbarSetup: Int { commonBase + 41 }
    public var ledBrightness: Int { commonBase + 42 }
    public var playerLEDs: Int { commonBase + 43 }
    public var lightbarRed: Int { commonBase + 44 }
    public var lightbarGreen: Int { commonBase + 45 }
    public var lightbarBlue: Int { commonBase + 46 }
}

// MARK: - Audio routing

/// Where the controller sends the two audio channels it receives over USB.
///
/// Values of the output path field as dualsensectl's `speaker` command names
/// them. The speaker is mono and plays the right channel.
public enum DSAudioOutputPath: UInt8 {
    /// Stereo to the headphone jack, speaker off. The power-on default.
    case headphones = 0
    case monoHeadphones = 1
    /// Left channel to the headphones, right channel to the speaker.
    case headphonesAndSpeaker = 2
    /// Right channel to the speaker, headphones off.
    case speaker = 3
}

/// The audio block of the output report. When a report carries one, the
/// audio control and speaker volume valid bits are set; when it carries none,
/// the controller keeps whatever routing it had.
///
/// Headphone and microphone volume are deliberately never touched: setting
/// their valid bits with a zero byte mutes them.
public struct DSAudioRoute: Equatable {
    public var path: DSAudioOutputPath
    public var speakerVolume: UInt8
    public var speakerPreampGain: UInt8

    /// The level the Linux driver programs when it routes to the speaker.
    /// The app scales the signal itself, so this stays fixed.
    public static let speakerVolumeLevel: UInt8 = 0x64
    public static let speakerPreampLevel: UInt8 = 2

    public static let speaker = DSAudioRoute(
        path: .speaker,
        speakerVolume: speakerVolumeLevel,
        speakerPreampGain: speakerPreampLevel
    )

    /// Back to the power-on routing: jack only, speaker silent.
    public static let headphones = DSAudioRoute(path: .headphones, speakerVolume: 0, speakerPreampGain: 0)

    func encode(into report: inout [UInt8], layout: DSOutputLayout) {
        report[layout.validFlag0] |= DualSenseProtocol.ValidFlag0.speakerVolumeEnable
            | DualSenseProtocol.ValidFlag0.audioControlEnable
        report[layout.validFlag1] |= DualSenseProtocol.ValidFlag1.audioControl2Enable
        report[layout.speakerVolume] = speakerVolume
        report[layout.audioControl] = (path.rawValue & 0x03) << DualSenseProtocol.audioOutputPathShift
        report[layout.audioControl2] = speakerPreampGain & DualSenseProtocol.speakerPreampGainMask
    }
}

// MARK: - Input report layout

/// Byte offsets into a DualSense input report, relative to the start of
/// `struct dualsense_input_report`.
public enum DSInputLayout {
    public static let leftStickX = 0
    public static let leftStickY = 1
    public static let rightStickX = 2
    public static let rightStickY = 3
    public static let triggerL2 = 4
    public static let triggerR2 = 5
    public static let sequenceNumber = 6
    public static let buttons = 7      // buttons[4]
    public static let gyro = 15        // 3 x le16
    public static let accel = 21       // 3 x le16
    public static let sensorTimestamp = 27
    public static let touchPoints = 32 // 2 x 4 bytes
    public static let status = 52      // status[3]
    public static let size = 63

    /// Index of the first payload byte inside a full report buffer.
    /// USB prefixes one byte (report ID), Bluetooth two (report ID + seq).
    public static func payloadOffset(isBluetooth: Bool) -> Int {
        isBluetooth ? 2 : 1
    }
}

// MARK: - IMU calibration

/// Factory calibration for one inertial axis.
///
/// The controller ships per-axis bias and sensitivity in feature report 0x05.
/// Applying it is what separates a gyro that reads zero at rest from one that
/// drifts, and it is the only way the raw counts become real units.
public struct DSAxisCalibration {
    public var bias: Int
    public var numerator: Int
    public var denominator: Int

    /// Identity-ish fallback used when a device reports unusable calibration,
    /// mirroring the kernel's sanity check.
    public static func fallback(range: Int) -> DSAxisCalibration {
        DSAxisCalibration(bias: 0, numerator: range, denominator: Int(Int16.max))
    }

    public func apply(_ raw: Int) -> Int {
        guard denominator != 0 else { return 0 }
        return numerator * (raw - bias) / denominator
    }
}

/// Calibration for the whole IMU, in report axis order.
public struct DSIMUCalibration {
    /// Gyro axes arrive as pitch, yaw, roll — not the pitch/roll/yaw order the
    /// name of the struct might suggest.
    public var gyro: [DSAxisCalibration]
    /// Accelerometer axes are x, y, z.
    public var accel: [DSAxisCalibration]

    public static let identity = DSIMUCalibration(
        gyro: Array(repeating: .fallback(range: Int(DualSenseProtocol.gyroRange)), count: 3),
        accel: Array(repeating: .fallback(range: Int(DualSenseProtocol.accelRange)), count: 3)
    )

    /// Parses feature report 0x05. `buffer` includes the leading report ID.
    public static func parse(featureReport buffer: [UInt8]) -> DSIMUCalibration? {
        guard buffer.count >= 35 else { return nil }
        func value(_ offset: Int) -> Int {
            Int(Int16(bitPattern: UInt16(buffer[offset]) | (UInt16(buffer[offset + 1]) << 8)))
        }

        let pitchBias = value(1), yawBias = value(3), rollBias = value(5)
        let pitchPlus = value(7), pitchMinus = value(9)
        let yawPlus = value(11), yawMinus = value(13)
        let rollPlus = value(15), rollMinus = value(17)
        let speedPlus = value(19), speedMinus = value(21)
        let accXPlus = value(23), accXMinus = value(25)
        let accYPlus = value(27), accYMinus = value(29)
        let accZPlus = value(31), accZMinus = value(33)

        let speed2x = speedPlus + speedMinus
        let gyroNumerator = speed2x * Int(DualSenseProtocol.gyroResolutionPerDegPerSec)

        func gyroAxis(_ plus: Int, _ minus: Int, _ bias: Int) -> DSAxisCalibration {
            let denominator = abs(plus - bias) + abs(minus - bias)
            guard denominator != 0 else {
                return .fallback(range: Int(DualSenseProtocol.gyroRange))
            }
            // The bias is folded into the sensitivity, so the axis reads zero
            // at rest without a separate offset.
            return DSAxisCalibration(bias: 0, numerator: gyroNumerator, denominator: denominator)
        }

        func accelAxis(_ plus: Int, _ minus: Int) -> DSAxisCalibration {
            let range2g = plus - minus
            guard range2g != 0 else {
                return .fallback(range: Int(DualSenseProtocol.accelRange))
            }
            return DSAxisCalibration(
                bias: plus - range2g / 2,
                numerator: 2 * Int(DualSenseProtocol.accelResolutionPerG),
                denominator: range2g
            )
        }

        return DSIMUCalibration(
            gyro: [
                gyroAxis(pitchPlus, pitchMinus, pitchBias),
                gyroAxis(yawPlus, yawMinus, yawBias),
                gyroAxis(rollPlus, rollMinus, rollBias),
            ],
            accel: [
                accelAxis(accXPlus, accXMinus),
                accelAxis(accYPlus, accYMinus),
                accelAxis(accZPlus, accZMinus),
            ]
        )
    }
}

// MARK: - Adaptive trigger effects

/// Encoder for the 11-byte adaptive trigger effect block.
///
/// Uses only the four officially recognised effect types. The `0x01` / `0x02` /
/// `0x06` "simple" variants are firmware leftovers with no parameter validation
/// and may be removed by a future firmware update.
public enum DSTriggerEffect {
    public static let blockSize = 11

    /// Effect type byte (offset 0 of the block).
    public enum EffectType: UInt8 {
        case off = 0x05
        case feedback = 0x21
        case weapon = 0x25
        case vibration = 0x26
        case machine = 0x27
    }

    /// Number of discrete trigger travel zones the firmware exposes.
    public static let zoneCount = 10
    /// Maximum per-zone force/amplitude level. Level 0 means "zone inactive".
    public static let maxLevel: UInt8 = 8

    public static func off(into report: inout [UInt8], at offset: Int) {
        guard offset + blockSize <= report.count else { return }
        report[offset] = EffectType.off.rawValue
        for i in 1..<blockSize { report[offset + i] = 0 }
    }

    /// Continuous resistance with an independent force level per zone.
    /// `levels` holds 10 entries in `0...8`; 0 disables that zone.
    public static func feedback(levels: [UInt8], into report: inout [UInt8], at offset: Int) {
        guard offset + blockSize <= report.count else { return }
        guard levels.count == zoneCount, levels.contains(where: { $0 > 0 }) else {
            off(into: &report, at: offset)
            return
        }

        var activeZones: UInt16 = 0
        var forceZones: UInt32 = 0
        for zone in 0..<zoneCount where levels[zone] > 0 {
            let force = UInt32((levels[zone] - 1) & 0x07)
            forceZones |= force << (3 * UInt32(zone))
            activeZones |= UInt16(1) << UInt16(zone)
        }

        report[offset + 0] = EffectType.feedback.rawValue
        report[offset + 1] = UInt8(activeZones & 0xFF)
        report[offset + 2] = UInt8((activeZones >> 8) & 0xFF)
        report[offset + 3] = UInt8(forceZones & 0xFF)
        report[offset + 4] = UInt8((forceZones >> 8) & 0xFF)
        report[offset + 5] = UInt8((forceZones >> 16) & 0xFF)
        report[offset + 6] = UInt8((forceZones >> 24) & 0xFF)
        for i in 7..<blockSize { report[offset + i] = 0 }
    }

    /// Resistance that builds from `startZone` and snaps at `endZone`.
    /// `startZone` is limited to `2...7`, `endZone` to `startZone+1...8`.
    public static func weapon(startZone: Int, endZone: Int, level: UInt8,
                              into report: inout [UInt8], at offset: Int) {
        guard offset + blockSize <= report.count else { return }
        let start = min(max(startZone, 2), 7)
        let end = min(max(endZone, start + 1), 8)
        guard level > 0 else {
            off(into: &report, at: offset)
            return
        }

        let zones = (UInt16(1) << UInt16(start)) | (UInt16(1) << UInt16(end))

        report[offset + 0] = EffectType.weapon.rawValue
        report[offset + 1] = UInt8(zones & 0xFF)
        report[offset + 2] = UInt8((zones >> 8) & 0xFF)
        report[offset + 3] = min(level, maxLevel) - 1
        for i in 4..<blockSize { report[offset + i] = 0 }
    }

    /// Automatic cycling vibration with a per-zone amplitude.
    /// `amplitudes` holds 10 entries in `0...8`; `frequency` is in Hz, `1...255`.
    public static func vibration(amplitudes: [UInt8], frequency: UInt8,
                                 into report: inout [UInt8], at offset: Int) {
        guard offset + blockSize <= report.count else { return }
        guard amplitudes.count == zoneCount,
              frequency > 0,
              amplitudes.contains(where: { $0 > 0 }) else {
            off(into: &report, at: offset)
            return
        }

        var activeZones: UInt16 = 0
        var amplitudeZones: UInt32 = 0
        for zone in 0..<zoneCount where amplitudes[zone] > 0 {
            let amplitude = UInt32((amplitudes[zone] - 1) & 0x07)
            amplitudeZones |= amplitude << (3 * UInt32(zone))
            activeZones |= UInt16(1) << UInt16(zone)
        }

        report[offset + 0] = EffectType.vibration.rawValue
        report[offset + 1] = UInt8(activeZones & 0xFF)
        report[offset + 2] = UInt8((activeZones >> 8) & 0xFF)
        report[offset + 3] = UInt8(amplitudeZones & 0xFF)
        report[offset + 4] = UInt8((amplitudeZones >> 8) & 0xFF)
        report[offset + 5] = UInt8((amplitudeZones >> 16) & 0xFF)
        report[offset + 6] = UInt8((amplitudeZones >> 24) & 0xFF)
        report[offset + 7] = 0
        report[offset + 8] = 0
        report[offset + 9] = frequency
        report[offset + 10] = 0
    }

    /// Two-amplitude oscillation between two zones — the firmware's own
    /// machine-gun effect. Amplitudes are `0...7`, period tunes the duty cycle.
    public static func machine(startZone: Int, endZone: Int,
                               amplitudeA: UInt8, amplitudeB: UInt8,
                               frequency: UInt8, period: UInt8,
                               into report: inout [UInt8], at offset: Int) {
        guard offset + blockSize <= report.count else { return }
        let start = min(max(startZone, 0), 8)
        let end = min(max(endZone, start + 1), 9)
        guard frequency > 0 else {
            off(into: &report, at: offset)
            return
        }

        let zones = (UInt16(1) << UInt16(start)) | (UInt16(1) << UInt16(end))
        let amplitudePair = ((amplitudeA & 0x07) << 0) | ((amplitudeB & 0x07) << 3)

        report[offset + 0] = EffectType.machine.rawValue
        report[offset + 1] = UInt8(zones & 0xFF)
        report[offset + 2] = UInt8((zones >> 8) & 0xFF)
        report[offset + 3] = amplitudePair
        report[offset + 4] = frequency
        report[offset + 5] = period
        for i in 6..<blockSize { report[offset + i] = 0 }
    }
}

// MARK: - Normalised value conversion

/// The UI and profiles work in normalised floats; the wire format works in
/// discrete zones and levels. Every conversion is saturating, because
/// `UInt8(someFloat)` traps on NaN and on anything outside `0...255`.
public enum DSScale {
    public static func byte(_ value: Float) -> UInt8 {
        guard value.isFinite else { return 0 }
        return UInt8(min(max((value * 255).rounded(), 0), 255))
    }

    public static func byte(_ value: Double) -> UInt8 {
        byte(Float(value))
    }

    public static func rawByte(_ value: Float) -> UInt8 {
        guard value.isFinite else { return 0 }
        return UInt8(min(max(value.rounded(), 0), 255))
    }

    /// Maps `0...1` onto a trigger travel zone `0...9`.
    public static func zone(_ value: Float) -> Int {
        guard value.isFinite else { return 0 }
        let scaled = (value * Float(DSTriggerEffect.zoneCount - 1)).rounded()
        return Int(min(max(scaled, 0), Float(DSTriggerEffect.zoneCount - 1)))
    }

    /// Maps `0...1` onto a force/amplitude level `0...8`, where 0 is inactive.
    public static func level(_ value: Float) -> UInt8 {
        guard value.isFinite else { return 0 }
        let scaled = (value * Float(DSTriggerEffect.maxLevel)).rounded()
        return UInt8(min(max(scaled, 0), Float(DSTriggerEffect.maxLevel)))
    }

    public static func clamp01(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
