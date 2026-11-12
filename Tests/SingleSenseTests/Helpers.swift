import XCTest
@testable import SingleSense

/// A system framework also exports `RGBColor`, so the app's type is spelled
/// out wherever tests mention it.
typealias AppColor = SingleSense.RGBColor

/// Shared helpers for reading fields out of a built output report.
extension XCTestCase {
    func makeTrigger(_ mode: TriggerModeType, _ configure: (inout SingleTriggerConfig) -> Void = { _ in }) -> SingleTriggerConfig {
        var config = SingleTriggerConfig(mode: mode)
        configure(&config)
        return config
    }

    /// The 11-byte effect block a configuration encodes to.
    func effectBlock(_ config: SingleTriggerConfig, layout: DSOutputLayout = .usb) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: layout.totalSize)
        config.encode(into: &report, at: layout.rightTriggerEffect)
        let start = layout.rightTriggerEffect
        return Array(report[start..<(start + DSTriggerEffect.blockSize)])
    }

    func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

extension DSHardwareState {
    /// A neutral state, for tests that only care about queue behaviour.
    static func stub(tag: UInt8 = 0, forceSend: Bool = false) -> DSHardwareState {
        DSHardwareState(
            lightbar: AppColor(red: 0, green: 0, blue: 0),
            playerLEDMask: tag,
            playerBrightness: .medium,
            micLED: .off,
            leftMotor: 0,
            rightMotor: 0,
            leftTrigger: SingleTriggerConfig(),
            rightTrigger: SingleTriggerConfig(),
            forceSend: forceSend
        )
    }
}

extension AudioLevels {
    static func uniform(_ value: Float, beat: Float = 0, kick: Float = 0, snare: Float = 0) -> AudioLevels {
        AudioLevels(bass: value, mid: value, treble: value, overall: value, beat: beat, kick: kick, snare: snare)
    }
}
