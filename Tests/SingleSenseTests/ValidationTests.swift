import XCTest
@testable import SingleSense

/// `UInt8(someFloat)` traps rather than saturating, and configurations reach
/// the send path straight from persisted JSON. Everything here guards that
/// boundary.
final class ValidationTests: XCTestCase {

    private let hostileJSON = """
    {
      "mode": "10-Zone Curve",
      "startPosition": 5.0,
      "endPosition": -3.0,
      "strength": 42.0,
      "startStrength": -1.0,
      "endStrength": 99.0,
      "frequency": 999999.0,
      "amplitude": -0.5,
      "custom10Zones": [3.0, -2.0, 0.5]
    }
    """

    func testDecodingClampsEveryField() throws {
        let config = try JSONDecoder().decode(
            SingleTriggerConfig.self, from: Data(hostileJSON.utf8)
        )
        XCTAssertEqual(config.startPosition, 1)
        XCTAssertEqual(config.endPosition, 0)
        XCTAssertEqual(config.strength, 1)
        XCTAssertEqual(config.startStrength, 0)
        XCTAssertEqual(config.endStrength, 1)
        XCTAssertEqual(config.amplitude, 0)
        XCTAssertEqual(config.frequency, 255)
    }

    func testDecodingNormalisesZoneArrayLength() throws {
        let config = try JSONDecoder().decode(
            SingleTriggerConfig.self, from: Data(hostileJSON.utf8)
        )
        XCTAssertEqual(config.custom10Zones.count, DSTriggerEffect.zoneCount)
        XCTAssertTrue(config.custom10Zones.allSatisfy { (0...1).contains($0) })
    }

    func testColourDecodingClamps() throws {
        let colour = try JSONDecoder().decode(
            AppColor.self, from: Data(#"{"red":7.5,"green":-2.0,"blue":0.5}"#.utf8)
        )
        XCTAssertEqual(colour.redByte, 255)
        XCTAssertEqual(colour.greenByte, 0)
        XCTAssertEqual(colour.blueByte, 128)
    }

    /// NaN compares false against every bound, so a plain min/max clamp lets
    /// it through into a trapping conversion.
    ///
    /// Every non-finite value resolves to zero rather than saturating. An
    /// infinity here means the data is corrupt, and a dark lightbar or a still
    /// motor is a safer reading of corrupt data than full brightness or full
    /// rumble.
    func testNonFiniteValuesAreNeutralised() {
        XCTAssertEqual(DSScale.byte(Float.nan), 0)
        XCTAssertEqual(DSScale.byte(Float.infinity), 0)
        XCTAssertEqual(DSScale.byte(-Float.infinity), 0)
        XCTAssertEqual(DSScale.rawByte(.nan), 0)
        XCTAssertEqual(DSScale.zone(.nan), 0)
        XCTAssertEqual(DSScale.level(.nan), 0)
        XCTAssertEqual(DSScale.clamp01(.nan), 0)

        let colour = AppColor(red: .nan, green: .infinity, blue: -.infinity)
        XCTAssertEqual(colour.redByte, 0)
        XCTAssertEqual(colour.greenByte, 0)
        XCTAssertEqual(colour.blueByte, 0)
    }

    func testScaleSaturatesRatherThanWrapping() {
        XCTAssertEqual(DSScale.byte(2.0), 255)
        XCTAssertEqual(DSScale.byte(-1.0), 0)
        XCTAssertEqual(DSScale.zone(9.0), DSTriggerEffect.zoneCount - 1)
        XCTAssertEqual(DSScale.level(9.0), DSTriggerEffect.maxLevel)
    }

    /// Every mode must survive hostile input and still emit a legal effect.
    func testEveryModeEncodesLegallyFromHostileInput() throws {
        let hostile = try JSONDecoder().decode(
            SingleTriggerConfig.self, from: Data(hostileJSON.utf8)
        )
        let legal: Set<UInt8> = Set(
            [DSTriggerEffect.EffectType.off, .feedback, .weapon, .vibration, .machine]
                .map(\.rawValue)
        )
        for mode in TriggerModeType.allCases {
            var config = hostile
            config.mode = mode
            XCTAssertTrue(legal.contains(effectBlock(config)[0]),
                          "\(mode.rawValue) emitted an unknown effect type")
        }
    }

    func testEncodingRefusesABufferTooShortToHoldABlock() {
        var tiny = [UInt8](repeating: 0, count: 8)
        makeTrigger(.weapon).encode(into: &tiny, at: 4)
        XCTAssertTrue(tiny.allSatisfy { $0 == 0 })
    }

    func testEncodingNeverWritesPastItsBlock() {
        var report = [UInt8](repeating: 0xEE, count: DSOutputLayout.usb.totalSize)
        let config = makeTrigger(.weapon) {
            $0.startPosition = 1; $0.endPosition = 1; $0.strength = 1
        }
        config.encode(into: &report, at: DSOutputLayout.usb.rightTriggerEffect)
        let justPast = DSOutputLayout.usb.rightTriggerEffect + DSTriggerEffect.blockSize
        XCTAssertEqual(report[justPast], 0xEE)
    }

    /// A zero-strength effect must disable the trigger rather than emit a
    /// malformed block the firmware would reject.
    func testZeroStrengthFallsBackToOff() {
        let feedback = makeTrigger(.feedback) { $0.strength = 0 }
        XCTAssertEqual(effectBlock(feedback)[0], DSTriggerEffect.EffectType.off.rawValue)

        let vibration = makeTrigger(.vibration) { $0.amplitude = 0; $0.frequency = 40 }
        XCTAssertEqual(effectBlock(vibration)[0], DSTriggerEffect.EffectType.off.rawValue)
    }
}
