import XCTest
@testable import SingleSense

/// Constants and algorithms transcribed from the two reference implementations
/// the protocol layer is built against: the Linux kernel driver
/// (`drivers/hid/hid-playstation.c`) and dualsensectl (nowrep/dualsensectl,
/// `main.c`), which is the one that actually implements adaptive triggers.
///
/// Nothing in `Reference` is derived from Single Sense — that is the point.
/// If someone changes an offset or a flag, these fail.
private enum Reference {
    static let flag0CompatibleVibration: UInt8 = 1 << 0
    static let flag0HapticsSelect: UInt8 = 1 << 1
    static let flag0RightTriggerMotorEnable: UInt8 = 1 << 2
    static let flag0LeftTriggerMotorEnable: UInt8 = 1 << 3
    static let flag0HeadphoneVolumeEnable: UInt8 = 1 << 4
    static let flag0SpeakerVolumeEnable: UInt8 = 1 << 5
    static let flag0MicrophoneVolumeEnable: UInt8 = 1 << 6
    static let flag0AudioControlEnable: UInt8 = 1 << 7

    static let flag1MicMuteLED: UInt8 = 1 << 0
    static let flag1PowerSave: UInt8 = 1 << 1
    static let flag1Lightbar: UInt8 = 1 << 2
    static let flag1ReleaseLEDs: UInt8 = 1 << 3
    static let flag1PlayerIndicator: UInt8 = 1 << 4
    static let flag1HapticLowPass: UInt8 = 1 << 5
    static let flag1VibrationAttenuation: UInt8 = 1 << 6
    static let flag1AudioControl2: UInt8 = 1 << 7

    static let flag2LEDBrightness: UInt8 = 1 << 0
    static let flag2LightbarSetup: UInt8 = 1 << 1
    static let flag2CompatibleVibration2: UInt8 = 1 << 2

    static let lightbarSetupLightOn: UInt8 = 1 << 0
    static let lightbarSetupLightOut: UInt8 = 1 << 1

    static let effectOff: UInt8 = 0x05
    static let effectFeedback: UInt8 = 0x21
    static let effectWeapon: UInt8 = 0x25
    static let effectVibration: UInt8 = 0x26
    static let effectMachine: UInt8 = 0x27

    static let outputTag: UInt8 = 0x10
    static let usbReportSize = 63
    static let btReportSize = 78

    /// Offsets within `struct dualsense_output_report_common`.
    static let commonValidFlag0 = 0
    static let commonValidFlag1 = 1
    static let commonMotorRight = 2
    static let commonMotorLeft = 3
    static let commonMuteButtonLED = 8
    static let commonPowerSaveControl = 9
    static let commonRightTrigger = 10
    static let commonLeftTrigger = 21
    static let commonValidFlag2 = 38
    static let commonLightbarSetup = 41
    static let commonLEDBrightness = 42
    static let commonPlayerLEDs = 43
    static let commonLightbarRed = 44
    static let commonLightbarGreen = 45
    static let commonLightbarBlue = 46

    /// `trigger_bitpacking_array()` followed by `command_trigger()`.
    static func bitpacked(mode: UInt8, strength: [UInt8], frequency: UInt8) -> [UInt8] {
        var strengthZones: UInt32 = 0
        var activeZones: UInt16 = 0
        for i in 0..<10 where strength[i] > 0 {
            strengthZones |= UInt32((strength[i] - 1) & 0x07) << (3 * UInt32(i))
            activeZones |= UInt16(1) << UInt16(i)
        }
        var block = [UInt8](repeating: 0, count: 11)
        block[0] = mode
        block[1] = UInt8(activeZones & 0xff)
        block[2] = UInt8((activeZones >> 8) & 0xff)
        block[3] = UInt8(strengthZones & 0xff)
        block[4] = UInt8((strengthZones >> 8) & 0xff)
        block[5] = UInt8((strengthZones >> 16) & 0xff)
        block[6] = UInt8((strengthZones >> 24) & 0xff)
        block[9] = frequency
        return block
    }

    static func feedback(position: Int, strength: UInt8) -> [UInt8] {
        var levels = [UInt8](repeating: 0, count: 10)
        for i in position..<10 { levels[i] = strength }
        return bitpacked(mode: effectFeedback, strength: levels, frequency: 0)
    }

    static func vibration(position: Int, amplitude: UInt8, frequency: UInt8) -> [UInt8] {
        var levels = [UInt8](repeating: 0, count: 10)
        for i in position..<10 { levels[i] = amplitude }
        return bitpacked(mode: effectVibration, strength: levels, frequency: frequency)
    }

    static func weapon(start: Int, end: Int, strength: UInt8) -> [UInt8] {
        let zones = UInt16((1 << start) | (1 << end))
        var block = [UInt8](repeating: 0, count: 11)
        block[0] = effectWeapon
        block[1] = UInt8(zones & 0xff)
        block[2] = UInt8((zones >> 8) & 0xff)
        block[3] = strength - 1
        return block
    }

    static func machine(start: Int, end: Int, amplitudeA: UInt8, amplitudeB: UInt8,
                        frequency: UInt8, period: UInt8) -> [UInt8] {
        let zones = UInt16((1 << start) | (1 << end))
        var block = [UInt8](repeating: 0, count: 11)
        block[0] = effectMachine
        block[1] = UInt8(zones & 0xff)
        block[2] = UInt8((zones >> 8) & 0xff)
        block[3] = UInt8((amplitudeA & 0x07) | ((amplitudeB & 0x07) << 3))
        block[4] = frequency
        block[5] = period
        return block
    }
}

final class DualSenseCtlConformanceTests: XCTestCase {

    func testValidFlag0BitsMatchReference() {
        XCTAssertEqual(DualSenseProtocol.ValidFlag0.compatibleVibration, Reference.flag0CompatibleVibration)
        XCTAssertEqual(DualSenseProtocol.ValidFlag0.hapticsSelect, Reference.flag0HapticsSelect)
        XCTAssertEqual(DualSenseProtocol.ValidFlag0.rightTriggerMotorEnable, Reference.flag0RightTriggerMotorEnable)
        XCTAssertEqual(DualSenseProtocol.ValidFlag0.leftTriggerMotorEnable, Reference.flag0LeftTriggerMotorEnable)
        XCTAssertEqual(DualSenseProtocol.ValidFlag0.headphoneVolumeEnable, Reference.flag0HeadphoneVolumeEnable)
        XCTAssertEqual(DualSenseProtocol.ValidFlag0.speakerVolumeEnable, Reference.flag0SpeakerVolumeEnable)
        XCTAssertEqual(DualSenseProtocol.ValidFlag0.micVolumeEnable, Reference.flag0MicrophoneVolumeEnable)
        XCTAssertEqual(DualSenseProtocol.ValidFlag0.audioControlEnable, Reference.flag0AudioControlEnable)
    }

    func testValidFlag1BitsMatchReference() {
        XCTAssertEqual(DualSenseProtocol.ValidFlag1.micMuteLEDControlEnable, Reference.flag1MicMuteLED)
        XCTAssertEqual(DualSenseProtocol.ValidFlag1.powerSaveControlEnable, Reference.flag1PowerSave)
        XCTAssertEqual(DualSenseProtocol.ValidFlag1.lightbarControlEnable, Reference.flag1Lightbar)
        XCTAssertEqual(DualSenseProtocol.ValidFlag1.releaseLEDs, Reference.flag1ReleaseLEDs)
        XCTAssertEqual(DualSenseProtocol.ValidFlag1.playerIndicatorControlEnable, Reference.flag1PlayerIndicator)
        XCTAssertEqual(DualSenseProtocol.ValidFlag1.hapticLowPassFilterEnable, Reference.flag1HapticLowPass)
        XCTAssertEqual(DualSenseProtocol.ValidFlag1.vibrationAttenuationEnable, Reference.flag1VibrationAttenuation)
        XCTAssertEqual(DualSenseProtocol.ValidFlag1.audioControl2Enable, Reference.flag1AudioControl2)
    }

    func testValidFlag2BitsMatchReference() {
        XCTAssertEqual(DualSenseProtocol.ValidFlag2.ledBrightnessControlEnable, Reference.flag2LEDBrightness)
        XCTAssertEqual(DualSenseProtocol.ValidFlag2.lightbarSetupControlEnable, Reference.flag2LightbarSetup)
        XCTAssertEqual(DualSenseProtocol.ValidFlag2.compatibleVibration2, Reference.flag2CompatibleVibration2)
        XCTAssertEqual(DualSenseProtocol.LightbarSetup.lightOn, Reference.lightbarSetupLightOn)
        XCTAssertEqual(DualSenseProtocol.LightbarSetup.lightOut, Reference.lightbarSetupLightOut)
    }

    func testEffectTypesMatchReference() {
        XCTAssertEqual(DSTriggerEffect.EffectType.off.rawValue, Reference.effectOff)
        XCTAssertEqual(DSTriggerEffect.EffectType.feedback.rawValue, Reference.effectFeedback)
        XCTAssertEqual(DSTriggerEffect.EffectType.weapon.rawValue, Reference.effectWeapon)
        XCTAssertEqual(DSTriggerEffect.EffectType.vibration.rawValue, Reference.effectVibration)
        XCTAssertEqual(DSTriggerEffect.EffectType.machine.rawValue, Reference.effectMachine)
    }

    func testReportSizesAndHeaders() {
        XCTAssertEqual(DualSenseProtocol.outputReportSizeUSB, Reference.usbReportSize)
        XCTAssertEqual(DualSenseProtocol.outputReportSizeBT, Reference.btReportSize)
        XCTAssertEqual(DualSenseProtocol.outputTag, Reference.outputTag)
        // Bluetooth prefixes report id, seq_tag and tag; USB only the id.
        XCTAssertEqual(DSOutputLayout.usb.commonBase, 1)
        XCTAssertEqual(DSOutputLayout.bluetooth.commonBase, 3)
        XCTAssertEqual(DSOutputLayout.bluetooth.sequenceTag, 1)
        XCTAssertEqual(DSOutputLayout.bluetooth.tag, 2)
    }

    /// Every field of `dualsense_output_report_common`, on both transports.
    /// This is the check that would have caught the original bug where USB and
    /// Bluetooth each used the other's base offset for half the report.
    func testCommonFieldOffsets() {
        for layout in [DSOutputLayout.usb, DSOutputLayout.bluetooth] {
            let base = layout.commonBase
            XCTAssertEqual(layout.validFlag0, base + Reference.commonValidFlag0)
            XCTAssertEqual(layout.validFlag1, base + Reference.commonValidFlag1)
            XCTAssertEqual(layout.motorRight, base + Reference.commonMotorRight)
            XCTAssertEqual(layout.motorLeft, base + Reference.commonMotorLeft)
            XCTAssertEqual(layout.muteButtonLED, base + Reference.commonMuteButtonLED)
            XCTAssertEqual(layout.powerSaveControl, base + Reference.commonPowerSaveControl)
            XCTAssertEqual(layout.rightTriggerEffect, base + Reference.commonRightTrigger)
            XCTAssertEqual(layout.leftTriggerEffect, base + Reference.commonLeftTrigger)
            XCTAssertEqual(layout.validFlag2, base + Reference.commonValidFlag2)
            XCTAssertEqual(layout.lightbarSetup, base + Reference.commonLightbarSetup)
            XCTAssertEqual(layout.ledBrightness, base + Reference.commonLEDBrightness)
            XCTAssertEqual(layout.playerLEDs, base + Reference.commonPlayerLEDs)
            XCTAssertEqual(layout.lightbarRed, base + Reference.commonLightbarRed)
            XCTAssertEqual(layout.lightbarGreen, base + Reference.commonLightbarGreen)
            XCTAssertEqual(layout.lightbarBlue, base + Reference.commonLightbarBlue)
        }
    }

    /// Both trigger blocks must fit inside `reserved2[27]` without colliding.
    func testTriggerBlocksDoNotOverlap() {
        for layout in [DSOutputLayout.usb, DSOutputLayout.bluetooth] {
            let rightEnd = layout.rightTriggerEffect + DSTriggerEffect.blockSize
            XCTAssertLessThanOrEqual(rightEnd, layout.leftTriggerEffect)
            let leftEnd = layout.leftTriggerEffect + DSTriggerEffect.blockSize
            XCTAssertLessThanOrEqual(leftEnd, layout.validFlag2)
        }
    }

    // MARK: - Effect encodings

    func testOffEncoding() {
        XCTAssertEqual(effectBlock(makeTrigger(.off)),
                       [Reference.effectOff] + [UInt8](repeating: 0, count: 10))
    }

    func testFeedbackEncoding() {
        let config = makeTrigger(.feedback) {
            $0.startPosition = 3.0 / 9.0
            $0.strength = 4.0 / 8.0
        }
        XCTAssertEqual(effectBlock(config), Reference.feedback(position: 3, strength: 4))
    }

    func testWeaponEncoding() {
        let config = makeTrigger(.weapon) {
            $0.startPosition = 3.0 / 9.0
            $0.endPosition = 7.0 / 9.0
            $0.strength = 6.0 / 8.0
        }
        XCTAssertEqual(effectBlock(config), Reference.weapon(start: 3, end: 7, strength: 6))
    }

    func testVibrationEncoding() {
        let config = makeTrigger(.vibration) {
            $0.startPosition = 2.0 / 9.0
            $0.amplitude = 5.0 / 8.0
            $0.frequency = 40
        }
        XCTAssertEqual(effectBlock(config),
                       Reference.vibration(position: 2, amplitude: 5, frequency: 40))
    }

    func testMachineGunEncoding() {
        let config = makeTrigger(.machineGun) {
            $0.startPosition = 2.0 / 9.0
            $0.strength = 6.0 / 8.0
        }
        XCTAssertEqual(effectBlock(config), Reference.machine(
            start: 2, end: 9, amplitudeA: 6, amplitudeB: 6,
            frequency: UInt8(SingleTriggerConfig.machineGunFrequency),
            period: SingleTriggerConfig.machineGunPeriod
        ))
    }

    func testTenZoneCurveEncoding() {
        let config = makeTrigger(.customCurve) {
            $0.custom10Zones = (0..<10).map { Float($0) / 8.0 }
        }
        XCTAssertEqual(effectBlock(config), Reference.bitpacked(
            mode: Reference.effectFeedback,
            strength: (0..<10).map { UInt8(min($0, 8)) },
            frequency: 0
        ))
    }

    /// Slope feedback has no dualsensectl equivalent, so assert its shape: a
    /// monotonic ramp packed as a normal Feedback effect.
    func testSlopeFeedbackRamps() {
        let config = makeTrigger(.slopeFeedback) {
            $0.startPosition = 0
            $0.endPosition = 8.0 / 9.0
            $0.startStrength = 1.0 / 8.0
            $0.endStrength = 1.0
        }
        let levels = config.slopeLevels()
        XCTAssertEqual(effectBlock(config),
                       Reference.bitpacked(mode: Reference.effectFeedback,
                                           strength: levels, frequency: 0))
        for (earlier, later) in zip(levels, levels.dropFirst()) {
            XCTAssertLessThanOrEqual(earlier, later, "ramp must not go backwards")
        }
        XCTAssertEqual(levels.last, 8)
    }
}
