import XCTest
@testable import SingleSense

/// The filter that stops identical reports flooding the link — and the rule
/// that kept adaptive triggers from applying.
final class SendDeduplicationTests: XCTestCase {

    private let report: [UInt8] = [0x31, 0x00, 0x10, 0x0E, 0x15, 0, 0, 0, 0x21, 0xFF]
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testIdenticalReportsAreSuppressed() {
        var filter = DSSendDeduplicator()
        XCTAssertTrue(filter.shouldSend(report, forced: false, now: start))
        filter.commit(report, at: start)

        for tick in 1...100 {
            let now = start.addingTimeInterval(Double(tick) * 0.016)
            XCTAssertFalse(filter.shouldSend(report, forced: false, now: now))
        }
    }

    func testKeepaliveResendsAfterTheWindow() {
        var filter = DSSendDeduplicator()
        filter.commit(report, at: start)
        let later = start.addingTimeInterval(DSSendDeduplicator.keepalive + 0.1)
        XCTAssertTrue(filter.shouldSend(report, forced: false, now: later))
    }

    func testDifferentReportsAlwaysPass() {
        var filter = DSSendDeduplicator()
        filter.commit(report, at: start)
        var other = report
        other[8] = 0x25
        XCTAssertTrue(filter.shouldSend(other, forced: false, now: start))
    }

    /// A refused write must not be remembered, or every retry is suppressed
    /// and the change is lost until the keepalive fires seconds later.
    func testARefusedReportDoesNotPoisonTheFilter() {
        var filter = DSSendDeduplicator()
        XCTAssertTrue(filter.shouldSend(report, forced: false, now: start))
        filter.invalidate()   // the link refused it

        let immediately = start.addingTimeInterval(0.02)
        XCTAssertTrue(filter.shouldSend(report, forced: false, now: immediately),
                      "the retry must not be suppressed")
    }

    /// Connect-time retries exist to catch a controller still finishing its
    /// handshake. They are byte-identical, so they only work when forced.
    func testForcedSendsBypassTheFilter() {
        var filter = DSSendDeduplicator()
        filter.commit(report, at: start)
        for delay in [0.1, 0.25, 0.6, 1.2] {
            let now = start.addingTimeInterval(delay)
            XCTAssertFalse(filter.shouldSend(report, forced: false, now: now))
            XCTAssertTrue(filter.shouldSend(report, forced: true, now: now))
        }
    }
}

/// Profiles survive a trip through disk without losing or corrupting settings.
final class ProfileRoundTripTests: XCTestCase {

    func testDefaultProfilesRoundTrip() throws {
        let originals = DefaultProfiles.createDefaults()
        let data = try JSONEncoder().encode(originals)
        let decoded = try JSONDecoder().decode([ControllerProfile].self, from: data)

        XCTAssertEqual(decoded.count, originals.count)
        for (original, restored) in zip(originals, decoded) {
            XCTAssertEqual(restored.id, original.id)
            XCTAssertEqual(restored.name, original.name)
            XCTAssertEqual(restored.lightbar, original.lightbar)
            XCTAssertEqual(restored.leftTrigger, original.leftTrigger)
            XCTAssertEqual(restored.rightTrigger, original.rightTrigger)
        }
    }

    /// Every shipped preset must encode to something the firmware accepts.
    func testEveryDefaultProfileEncodesLegally() {
        let legal: Set<UInt8> = Set(
            [DSTriggerEffect.EffectType.off, .feedback, .weapon, .vibration, .machine]
                .map(\.rawValue)
        )
        for profile in DefaultProfiles.createDefaults() {
            for (side, config) in [("left", profile.leftTrigger), ("right", profile.rightTrigger)] {
                let block = effectBlock(config)
                XCTAssertTrue(legal.contains(block[0]),
                              "\(profile.name) \(side) emitted effect 0x\(String(block[0], radix: 16))")
            }
        }
    }

    func testEveryTriggerPresetEncodesLegally() {
        let legal: Set<UInt8> = Set(
            [DSTriggerEffect.EffectType.off, .feedback, .weapon, .vibration, .machine]
                .map(\.rawValue)
        )
        for preset in TriggerPresets.all {
            XCTAssertTrue(legal.contains(effectBlock(preset.leftConfig)[0]), "\(preset.name) left")
            XCTAssertTrue(legal.contains(effectBlock(preset.rightConfig)[0]), "\(preset.name) right")
        }
    }
}
