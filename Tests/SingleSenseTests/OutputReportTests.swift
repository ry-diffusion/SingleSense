import XCTest
@testable import SingleSense

/// End-to-end checks on the bytes `HIDDriver` puts on the wire.
final class OutputReportTests: XCTestCase {

    private func build(
        layout: DSOutputLayout,
        v2: Bool = false,
        colour: AppColor = AppColor(red: 1, green: 0, blue: 0),
        mask: UInt8 = 0x04,
        brightness: PlayerLEDBrightness = .medium,
        mic: MicLEDMode = .off,
        left: UInt8 = 0,
        right: UInt8 = 0,
        leftTrigger: SingleTriggerConfig = SingleTriggerConfig(),
        rightTrigger: SingleTriggerConfig = SingleTriggerConfig()
    ) -> [UInt8] {
        HIDDriver.buildOutputReport(
            layout: layout, useVibrationV2: v2, lightbar: colour,
            playerLEDMask: mask, playerBrightness: brightness, micLED: mic,
            leftMotor: left, rightMotor: right,
            leftTrigger: leftTrigger, rightTrigger: rightTrigger
        )
    }

    func testReportIDAndLength() {
        let usb = build(layout: .usb)
        XCTAssertEqual(usb.count, 63)
        XCTAssertEqual(usb[0], 0x02)

        let bt = build(layout: .bluetooth)
        XCTAssertEqual(bt.count, 78)
        XCTAssertEqual(bt[0], 0x31)
        // "Tag must be set", per the kernel. Without it the report is ignored.
        XCTAssertEqual(bt[DSOutputLayout.bluetooth.tag], DualSenseProtocol.outputTag)
    }

    /// The regression that stopped adaptive triggers working: the enable bits
    /// were dropped while removing the audio bits.
    func testTriggerEnableBitsAreSet() {
        for layout in [DSOutputLayout.usb, DSOutputLayout.bluetooth] {
            let flag0 = build(layout: layout)[layout.validFlag0]
            XCTAssertNotEqual(flag0 & DualSenseProtocol.ValidFlag0.rightTriggerMotorEnable, 0,
                              "right trigger effects are ignored without bit 2")
            XCTAssertNotEqual(flag0 & DualSenseProtocol.ValidFlag0.leftTriggerMotorEnable, 0,
                              "left trigger effects are ignored without bit 3")
        }
    }

    /// Enabling audio control with the volume bytes left at zero mutes the
    /// controller's speaker, headphone and microphone.
    func testAudioControlBitsAreNeverSet() {
        for layout in [DSOutputLayout.usb, DSOutputLayout.bluetooth] {
            let report = build(layout: layout)
            let flag0 = report[layout.validFlag0]
            let audioBits = DualSenseProtocol.ValidFlag0.headphoneVolumeEnable
                | DualSenseProtocol.ValidFlag0.speakerVolumeEnable
                | DualSenseProtocol.ValidFlag0.micVolumeEnable
                | DualSenseProtocol.ValidFlag0.audioControlEnable
            XCTAssertEqual(flag0 & audioBits, 0, "would mute the controller")
            XCTAssertEqual(report[layout.headphoneVolume], 0)
            XCTAssertEqual(report[layout.speakerVolume], 0)
            XCTAssertEqual(report[layout.micVolume], 0)
        }
    }

    func testLEDControlBitsAreSet() {
        for layout in [DSOutputLayout.usb, DSOutputLayout.bluetooth] {
            let report = build(layout: layout)
            let flag1 = report[layout.validFlag1]
            XCTAssertNotEqual(flag1 & DualSenseProtocol.ValidFlag1.lightbarControlEnable, 0)
            XCTAssertNotEqual(flag1 & DualSenseProtocol.ValidFlag1.playerIndicatorControlEnable, 0)
            XCTAssertNotEqual(flag1 & DualSenseProtocol.ValidFlag1.micMuteLEDControlEnable, 0)
            // led_brightness is ignored without its own enable bit.
            XCTAssertNotEqual(report[layout.validFlag2] & DualSenseProtocol.ValidFlag2.ledBrightnessControlEnable, 0)
        }
    }

    /// Newer firmware takes a different rumble path; the kernel switches at
    /// update version 2.21.
    func testRumblePathFollowsFirmwareVersion() {
        for layout in [DSOutputLayout.usb, DSOutputLayout.bluetooth] {
            let v1 = build(layout: layout, v2: false)
            XCTAssertNotEqual(v1[layout.validFlag0] & DualSenseProtocol.ValidFlag0.compatibleVibration, 0)
            XCTAssertEqual(v1[layout.validFlag2] & DualSenseProtocol.ValidFlag2.compatibleVibration2, 0)

            let v2 = build(layout: layout, v2: true)
            XCTAssertEqual(v2[layout.validFlag0] & DualSenseProtocol.ValidFlag0.compatibleVibration, 0)
            XCTAssertNotEqual(v2[layout.validFlag2] & DualSenseProtocol.ValidFlag2.compatibleVibration2, 0)
        }
    }

    /// Colours landed on the wrong channels when USB used Bluetooth's offsets:
    /// asking for red produced green, and blue was lost entirely.
    func testLightbarChannelsAreNotShifted() {
        for layout in [DSOutputLayout.usb, DSOutputLayout.bluetooth] {
            let report = build(layout: layout, colour: AppColor(red: 1, green: 0, blue: 0))
            XCTAssertEqual(report[layout.lightbarRed], 255)
            XCTAssertEqual(report[layout.lightbarGreen], 0)
            XCTAssertEqual(report[layout.lightbarBlue], 0)

            let blue = build(layout: layout, colour: AppColor(red: 0, green: 0, blue: 1))
            XCTAssertEqual(blue[layout.lightbarBlue], 255, "blue channel must survive")
        }
    }

    func testMotorsAreNotSwapped() {
        for layout in [DSOutputLayout.usb, DSOutputLayout.bluetooth] {
            let report = build(layout: layout, left: 0x11, right: 0x99)
            XCTAssertEqual(report[layout.motorLeft], 0x11)
            XCTAssertEqual(report[layout.motorRight], 0x99)
        }
    }

    func testPlayerLEDsAreInstantAndMaskedCorrectly() {
        for layout in [DSOutputLayout.usb, DSOutputLayout.bluetooth] {
            let report = build(layout: layout, mask: 0x15)
            // Bit 5 suppresses the slow fade-in.
            XCTAssertEqual(report[layout.playerLEDs], 0x15 | DualSenseProtocol.playerLEDInstant)

            // "Off" brightness darkens the row rather than sending an
            // out-of-range brightness level.
            let dark = build(layout: layout, mask: 0x1F, brightness: .off)
            XCTAssertEqual(dark[layout.playerLEDs], 0)
            XCTAssertLessThanOrEqual(dark[layout.ledBrightness], 2)
        }
    }

    func testBrightnessLevelsStayInFirmwareRange() {
        for brightness in PlayerLEDBrightness.allCases {
            XCTAssertLessThanOrEqual(brightness.rawValueByte, 2,
                                     "\(brightness.rawValue) is outside 0...2")
        }
    }

    func testTriggerEffectsLandInTheirOwnBlocks() {
        let left = makeTrigger(.feedback) { $0.startPosition = 0; $0.strength = 1 }
        let right = makeTrigger(.weapon) {
            $0.startPosition = 3.0 / 9.0; $0.endPosition = 7.0 / 9.0; $0.strength = 1
        }
        for layout in [DSOutputLayout.usb, DSOutputLayout.bluetooth] {
            let report = build(layout: layout, leftTrigger: left, rightTrigger: right)
            XCTAssertEqual(report[layout.leftTriggerEffect], DSTriggerEffect.EffectType.feedback.rawValue)
            XCTAssertEqual(report[layout.rightTriggerEffect], DSTriggerEffect.EffectType.weapon.rawValue)
        }
    }

    /// `dualsense_reset_leds`: nothing but the lightbar setup command, or the
    /// controller keeps its startup animation and ignores LED programming.
    func testLEDResetCarriesOnlyTheSetupCommand() {
        for layout in [DSOutputLayout.usb, DSOutputLayout.bluetooth] {
            let report = HIDDriver.buildLEDResetReport(layout: layout)
            XCTAssertEqual(report[layout.validFlag2], DualSenseProtocol.ValidFlag2.lightbarSetupControlEnable)
            XCTAssertEqual(report[layout.lightbarSetup], DualSenseProtocol.LightbarSetup.lightOut)
            XCTAssertEqual(report[layout.validFlag0], 0)
            XCTAssertEqual(report[layout.validFlag1], 0)
            XCTAssertEqual(report[layout.lightbarRed], 0)
        }
    }

    // MARK: - Bluetooth CRC

    /// Matches `crc32_le(0xFFFFFFFF, seed=0xA2)` over everything but the CRC,
    /// stored little-endian.
    func testBluetoothCRCMatchesIndependentImplementation() {
        var report = build(layout: .bluetooth)
        report[DSOutputLayout.bluetooth.sequenceTag] = 5 << 4
        DualSenseChecksum.appendBluetoothCRC(to: &report)

        let payload = Array(report[0..<74])
        var crc: UInt32 = 0xFFFFFFFF
        for byte in [DualSenseChecksum.outputSeed] + payload {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
            }
        }
        let expected = ~crc

        let stored = UInt32(report[74]) | (UInt32(report[75]) << 8)
            | (UInt32(report[76]) << 16) | (UInt32(report[77]) << 24)
        XCTAssertEqual(stored, expected)
    }

    func testCRCIsOnlyAppendedToFullSizeBluetoothReports() {
        var short = [UInt8](repeating: 0, count: 63)
        DualSenseChecksum.appendBluetoothCRC(to: &short)
        XCTAssertTrue(short.allSatisfy { $0 == 0 }, "USB reports carry no CRC")
    }
}
