import XCTest
@testable import SingleSense

/// The controller speaker: its wire encoding, its playback buffer and its
/// saved settings.
final class SpeakerTests: XCTestCase {

    // MARK: - Output report

    private func build(layout: DSOutputLayout, route: DSAudioRoute?) -> [UInt8] {
        HIDDriver.buildOutputReport(
            layout: layout, useVibrationV2: false, lightbar: AppColor(red: 0, green: 0, blue: 0),
            playerLEDMask: 0, playerBrightness: .medium, micLED: .off,
            leftMotor: 0, rightMotor: 0,
            leftTrigger: SingleTriggerConfig(), rightTrigger: SingleTriggerConfig(),
            audioRoute: route
        )
    }

    /// dualsensectl's `speaker internal`: output path 3 in bits 4-5.
    func testSpeakerRouteEncoding() {
        for layout in [DSOutputLayout.usb, DSOutputLayout.bluetooth] {
            let report = build(layout: layout, route: .speaker)
            let flag0 = report[layout.validFlag0]
            XCTAssertNotEqual(flag0 & DualSenseProtocol.ValidFlag0.audioControlEnable, 0)
            XCTAssertNotEqual(flag0 & DualSenseProtocol.ValidFlag0.speakerVolumeEnable, 0)
            XCTAssertNotEqual(report[layout.validFlag1] & DualSenseProtocol.ValidFlag1.audioControl2Enable, 0)
            XCTAssertEqual(report[layout.audioControl], 0x30)
            XCTAssertEqual(report[layout.speakerVolume], DSAudioRoute.speakerVolumeLevel)
            XCTAssertEqual(report[layout.audioControl2], DSAudioRoute.speakerPreampLevel)
        }
    }

    /// A zero byte behind these bits mutes the jack and the microphone, so
    /// routing the speaker must never switch them on.
    func testRouteNeverTouchesHeadphoneOrMicVolume() {
        for route in [DSAudioRoute.speaker, .headphones] {
            let layout = DSOutputLayout.usb
            let flag0 = build(layout: layout, route: route)[layout.validFlag0]
            XCTAssertEqual(flag0 & DualSenseProtocol.ValidFlag0.headphoneVolumeEnable, 0)
            XCTAssertEqual(flag0 & DualSenseProtocol.ValidFlag0.micVolumeEnable, 0)
        }
    }

    func testHeadphoneRouteSilencesSpeaker() {
        let layout = DSOutputLayout.usb
        let report = build(layout: layout, route: .headphones)
        XCTAssertEqual(report[layout.audioControl], 0x00)
        XCTAssertEqual(report[layout.speakerVolume], 0)
    }

    /// Without a route the audio block stays exactly as before the feature.
    func testNoRouteLeavesAudioBlockAlone() {
        let layout = DSOutputLayout.usb
        let withRoute = build(layout: layout, route: nil)
        let audioBits = DualSenseProtocol.ValidFlag0.speakerVolumeEnable | DualSenseProtocol.ValidFlag0.audioControlEnable
        XCTAssertEqual(withRoute[layout.validFlag0] & audioBits, 0)
        XCTAssertEqual(withRoute[layout.validFlag1] & DualSenseProtocol.ValidFlag1.audioControl2Enable, 0)
        XCTAssertEqual(withRoute[layout.audioControl], 0)
    }

    /// Lighting and triggers must come through the audio block untouched.
    func testRouteDoesNotDisturbOtherFields() {
        let layout = DSOutputLayout.bluetooth
        var without = build(layout: layout, route: nil)
        var with = build(layout: layout, route: .speaker)
        for offset in [layout.validFlag0, layout.validFlag1, layout.speakerVolume, layout.audioControl, layout.audioControl2] {
            without[offset] = 0
            with[offset] = 0
        }
        XCTAssertEqual(hex(without), hex(with))
    }

    // MARK: - Ring buffer

    private func write(_ ring: SpeakerRingBuffer, frames: Int, left: Float, right: Float) {
        ring.write(frames: frames) { _ in (left, right) }
    }

    private func read(_ ring: SpeakerRingBuffer, frames: Int) -> [Float] {
        var out = [Float](repeating: .nan, count: frames * 2)
        out.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, frames: frames) }
        return out
    }

    func testStaysSilentUntilPrimed() {
        let ring = SpeakerRingBuffer(capacity: 64, target: 8, ceiling: 32)
        write(ring, frames: 7, left: 1, right: 1)
        XCTAssertEqual(read(ring, frames: 4), [Float](repeating: 0, count: 8))
        XCTAssertEqual(ring.bufferedFrames, 7, "priming must not consume anything")

        write(ring, frames: 1, left: 1, right: 1)
        XCTAssertEqual(read(ring, frames: 4), [Float](repeating: 1, count: 8))
    }

    func testMonoFoldDownAndGain() {
        let ring = SpeakerRingBuffer(capacity: 64, target: 1, ceiling: 32)
        ring.setParameters(gain: 0.5, mono: true)
        write(ring, frames: 2, left: 1, right: 0)
        XCTAssertEqual(read(ring, frames: 2), [0.25, 0.25, 0.25, 0.25])

        ring.setParameters(gain: 1, mono: false)
        write(ring, frames: 1, left: 1, right: -1)
        XCTAssertEqual(read(ring, frames: 1), [1, -1])
    }

    func testUnderrunPadsWithSilenceAndRePrimes() {
        let ring = SpeakerRingBuffer(capacity: 64, target: 4, ceiling: 32)
        write(ring, frames: 5, left: 1, right: 1)
        let out = read(ring, frames: 8)
        XCTAssertEqual(Array(out[0..<10]), [Float](repeating: 1, count: 10))
        XCTAssertEqual(Array(out[10...]), [Float](repeating: 0, count: 6))

        // Starved: it waits for a full target again rather than stuttering.
        write(ring, frames: 2, left: 1, right: 1)
        XCTAssertEqual(read(ring, frames: 2), [Float](repeating: 0, count: 4))
    }

    /// A producer running ahead must not let latency grow without bound.
    func testOverfillDropsBackToTarget() {
        let ring = SpeakerRingBuffer(capacity: 64, target: 8, ceiling: 16)
        write(ring, frames: 16, left: 0, right: 0)
        XCTAssertEqual(ring.bufferedFrames, 16)
        write(ring, frames: 1, left: 1, right: 1)
        XCTAssertEqual(ring.bufferedFrames, 8)
        // The newest audio is what survives.
        let out = read(ring, frames: 8)
        XCTAssertEqual(Array(out.suffix(2)), [1, 1])
    }

    func testNonFiniteSamplesBecomeSilence() {
        let ring = SpeakerRingBuffer(capacity: 16, target: 1, ceiling: 8)
        write(ring, frames: 1, left: .nan, right: .infinity)
        XCTAssertEqual(read(ring, frames: 1), [0, 0])
    }

    /// With a subwoofer, the speaker's half of the crossover drops the bass
    /// and keeps the rest.
    func testCrossoverHighPassOnTheSpeaker() {
        func response(_ hz: Float, crossover: Float?) -> Float {
            let ring = SpeakerRingBuffer(capacity: 16_384, target: 1, ceiling: 16_384)
            ring.setParameters(gain: 1, mono: true)
            ring.setHighPass(crossover, sampleRate: 48_000)
            let frames = 9_600
            ring.write(frames: frames) { i in
                let v = 0.5 * sinf(2 * .pi * hz * Float(i) / 48_000)
                return (v, v)
            }
            let out = read(ring, frames: frames)
            let settled = stride(from: frames, to: frames * 2, by: 2).map { out[$0] }
            return (settled.reduce(0) { $0 + $1 * $1 } / Float(settled.count)).squareRoot()
        }
        let fullRange = response(50, crossover: nil)
        XCTAssertLessThan(response(50, crossover: 150), fullRange * 0.05)
        XCTAssertEqual(response(2_000, crossover: 150), response(2_000, crossover: nil), accuracy: 0.01)
    }

    // MARK: - Device matching

    func testDeviceMatching() {
        XCTAssertTrue(CoreAudioQuery.isDualSense(name: "DualSense Wireless Controller", modelUID: ""))
        XCTAssertTrue(CoreAudioQuery.isDualSense(name: "Couch speaker", modelUID: "Wireless Controller:054C:0CE6"))
        XCTAssertTrue(CoreAudioQuery.isDualSense(name: "Edge", modelUID: "DualSense Edge:054c:0df2"))
        // Sony makes headsets too.
        XCTAssertFalse(CoreAudioQuery.isDualSense(name: "PULSE 3D", modelUID: "PULSE 3D:054C:0CD7"))
        XCTAssertFalse(CoreAudioQuery.isDualSense(name: "MacBook Pro Speakers", modelUID: "Speakers:0000:0000"))
    }

    // MARK: - Settings

    func testSessionWithoutSpeakerKeyDefaultsToOff() throws {
        let json = #"{"triggersLinked": true}"#
        let settings = try JSONDecoder().decode(SessionSettings.self, from: Data(json.utf8))
        XCTAssertFalse(settings.speaker.isEnabled)
        XCTAssertEqual(settings.speaker.volume, SpeakerConfiguration().volume)
        XCTAssertTrue(settings.triggersLinked)
    }

    func testSpeakerSettingsRoundTripAndClamp() throws {
        var settings = SessionSettings()
        settings.speaker.isEnabled = true
        settings.speaker.volume = 0.3
        let decoded = try JSONDecoder().decode(SessionSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.speaker, settings.speaker)

        let loud = #"{"speaker": {"isEnabled": true, "volume": 7}}"#
        let clamped = try JSONDecoder().decode(SessionSettings.self, from: Data(loud.utf8))
        XCTAssertEqual(clamped.speaker.volume, 1)
        XCTAssertTrue(clamped.speaker.isEnabled)
    }

    func testGainCurve() {
        var config = SpeakerConfiguration()
        config.volume = 0
        XCTAssertEqual(config.gain, 0)
        config.volume = 0.5
        XCTAssertEqual(config.gain, 0.25, accuracy: 1e-6)
        config.volume = 1
        XCTAssertEqual(config.gain, 1)
    }
}
