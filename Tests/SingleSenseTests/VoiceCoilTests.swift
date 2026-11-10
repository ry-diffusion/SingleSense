import XCTest
@testable import SingleSense

/// The voice-coil path: synthesis, the mixer's channel layout, the music feed
/// and the Music Sync routing decision. Nothing here opens a device.
final class VoiceCoilTests: XCTestCase {

    private static let rate: Float = 48_000

    private func peak(_ samples: [Float]) -> Float { samples.reduce(0) { max($0, abs($1)) } }

    /// RMS frequency: a sine reads as its own frequency.
    private func centroidHz(_ samples: [Float]) -> Float {
        var energy: Double = 0, difference: Double = 0
        for i in 1..<samples.count {
            let x = Double(samples[i])
            let d = x - Double(samples[i - 1])
            energy += x * x
            difference += d * d
        }
        guard energy > 0 else { return 0 }
        return Float((difference / energy).squareRoot() * Double(Self.rate) / (2 * Double.pi))
    }

    private func render(_ mixer: VoiceCoilMixer, frames: Int, channels: Int = 4) -> [Float] {
        var out = [Float](repeating: .nan, count: frames * channels)
        out.withUnsafeMutableBufferPointer { mixer.render(into: $0.baseAddress!, frames: frames, channels: channels) }
        return out
    }

    private func channel(_ buffer: [Float], _ index: Int, of channels: Int = 4) -> [Float] {
        stride(from: index, to: buffer.count, by: channels).map { buffer[$0] }
    }

    // MARK: - Synthesis

    func testEveryPresetIsAudibleBoundedAndEndsQuietly() {
        for preset in HapticPreset.allCases {
            let cues = preset.cues()
            XCTAssertFalse(cues.isEmpty, preset.rawValue)
            for cue in cues {
                XCTAssertFalse(cue.samples.isEmpty, preset.rawValue)
                XCTAssertTrue(cue.samples.allSatisfy(\.isFinite), preset.rawValue)
                let loudest = peak(cue.samples)
                XCTAssertGreaterThan(loudest, 0.05, preset.rawValue)
                XCTAssertLessThanOrEqual(loudest, 1.0001, preset.rawValue)
                XCTAssertEqual(cue.samples.last ?? 1, 0, accuracy: 1e-6, "\(preset.rawValue) must fade to zero")
                XCTAssertLessThanOrEqual(abs(cue.pan), 1, preset.rawValue)
                XCTAssertGreaterThanOrEqual(cue.delayMs, 0, preset.rawValue)
            }
        }
    }

    func testSynthesisIsDeterministic() {
        for preset in HapticPreset.allCases {
            XCTAssertEqual(preset.cues().map(\.samples), preset.cues().map(\.samples), preset.rawValue)
        }
    }

    /// The coils have nothing useful to say up high; every effect lives in
    /// the band they actually reproduce.
    func testPresetsStayInTheCoilBand() {
        for preset in HapticPreset.allCases {
            for cue in preset.cues() {
                XCTAssertLessThan(centroidHz(cue.samples), 600, preset.rawValue)
            }
        }
        let explosion = HapticPreset.explosion.cues()[0].samples
        let click = HapticPreset.click.cues()[0].samples
        XCTAssertLessThan(centroidHz(explosion), centroidHz(click), "an explosion is lower than a click")
        XCTAssertGreaterThan(explosion.count, click.count * 10, "and much longer")
    }

    func testFootstepsAlternateGrips() {
        let pans = HapticPreset.footsteps.cues().map(\.pan)
        XCTAssertEqual(pans, [-1, 1, -1, 1])
    }

    func testDecayingSineHitsItsFrequency() {
        var wave = HapticWave(milliseconds: 200)
        wave.addSine(200, 1, attackMs: 1, decayMs: 400)
        XCTAssertEqual(centroidHz(wave.finished(peak: 1)), 200, accuracy: 10)
    }

    // MARK: - Mixer

    func testOnlyTheCoilChannelsCarrySignal() {
        let mixer = VoiceCoilMixer()
        mixer.setMasterGain(1)
        mixer.play([HapticCue(samples: [Float](repeating: 0.5, count: 64))])
        let out = render(mixer, frames: 64)
        XCTAssertEqual(channel(out, 0), [Float](repeating: 0, count: 64), "headphone/speaker left untouched")
        XCTAssertEqual(channel(out, 1), [Float](repeating: 0, count: 64), "headphone/speaker right untouched")
        XCTAssertEqual(channel(out, 2), [Float](repeating: 0.5, count: 64))
        XCTAssertEqual(channel(out, 3), [Float](repeating: 0.5, count: 64))
    }

    func testPanSelectsAGrip() {
        let mixer = VoiceCoilMixer()
        mixer.setMasterGain(1)
        mixer.play([HapticCue(samples: [0.5, 0.5])], pan: -1)
        var out = render(mixer, frames: 2)
        XCTAssertEqual(channel(out, 2), [0.5, 0.5])
        XCTAssertEqual(channel(out, 3), [0, 0])

        mixer.play([HapticCue(samples: [0.5, 0.5], pan: 1)])
        out = render(mixer, frames: 2)
        XCTAssertEqual(channel(out, 2), [0, 0])
        XCTAssertEqual(channel(out, 3), [0.5, 0.5])
    }

    func testDelayAndVoiceCompletion() {
        let mixer = VoiceCoilMixer()
        mixer.setMasterGain(1)
        let delayFrames = 48 // 1 ms
        mixer.play([HapticCue(samples: [0.25, 0.25, 0.25], delayMs: 1)])
        XCTAssertEqual(mixer.activeVoices, 1)

        let out = render(mixer, frames: delayFrames + 8)
        let left = channel(out, 2)
        XCTAssertEqual(Array(left[0..<delayFrames]), [Float](repeating: 0, count: delayFrames))
        XCTAssertEqual(Array(left[delayFrames..<(delayFrames + 3)]), [0.25, 0.25, 0.25])
        XCTAssertEqual(Array(left[(delayFrames + 3)...]), [Float](repeating: 0, count: 5))
        XCTAssertEqual(mixer.activeVoices, 0)
    }

    /// A delay that spans several buffers must carry over between them.
    func testDelaySpanningBuffers() {
        let mixer = VoiceCoilMixer()
        mixer.setMasterGain(1)
        mixer.play([HapticCue(samples: [0.5], delayMs: 2)]) // 96 frames
        XCTAssertEqual(channel(render(mixer, frames: 64), 2).max(), 0)
        let second = channel(render(mixer, frames: 64), 2)
        XCTAssertEqual(second[32], 0.5)
        XCTAssertEqual(second.filter { $0 != 0 }.count, 1)
    }

    func testMasterGainAndSoftClip() {
        let mixer = VoiceCoilMixer()
        mixer.setMasterGain(0.5)
        mixer.play([HapticCue(samples: [0.4])])
        XCTAssertEqual(channel(render(mixer, frames: 1), 2), [0.2])

        // Four loud voices at once must not exceed the coil's range.
        mixer.setMasterGain(1)
        mixer.play((0..<4).map { _ in HapticCue(samples: [0.9, 0.9]) })
        let loud = channel(render(mixer, frames: 2), 2)
        XCTAssertTrue(loud.allSatisfy { $0 <= 1 && $0 > 0.8 })
    }

    func testFewerThanFourChannelsStaysSilent() {
        let mixer = VoiceCoilMixer()
        mixer.play([HapticCue(samples: [0.5, 0.5])])
        XCTAssertEqual(render(mixer, frames: 2, channels: 2), [0, 0, 0, 0])
    }

    func testVoicesAreCappedAndRecycled() {
        let mixer = VoiceCoilMixer()
        let long = [Float](repeating: 0.1, count: 1_000)
        mixer.play((0..<(VoiceCoilMixer.maxVoices + 10)).map { _ in HapticCue(samples: long) })
        XCTAssertEqual(mixer.activeVoices, VoiceCoilMixer.maxVoices)
        mixer.clear()
        XCTAssertEqual(mixer.activeVoices, 0)
    }

    // MARK: - Music feed

    private func sine(_ hz: Float, frames: Int, rate: Float = 48_000) -> [Float] {
        (0..<frames).map { 0.3 * sinf(2 * .pi * hz * Float($0) / rate) }
    }

    private func rms(_ x: ArraySlice<Float>) -> Float {
        (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot()
    }

    /// Feeds and renders in alternating 512-frame blocks, the way the capture
    /// and render threads take turns, then measures the settled half.
    private func musicResponse(_ hz: Float, style: CoilMusicStyle, coil: Int) -> Float {
        let mixer = VoiceCoilMixer()
        mixer.setMusic(style: style, gain: 1)
        let block = 512, blocks = 40
        let input = sine(hz, frames: block * blocks)
        var out: [Float] = []
        for b in 0..<blocks {
            input[(b * block)..<((b + 1) * block)].withUnsafeBufferPointer {
                mixer.feedMusic($0, sampleRate: 48_000)
            }
            out += channel(render(mixer, frames: block), coil)
        }
        return rms(out[(out.count / 2)...])
    }

    func testBassStyleKeepsTheBassAndDropsTheRest() {
        let bass = musicResponse(60, style: .bass, coil: 2)
        let treble = musicResponse(2_000, style: .bass, coil: 2)
        XCTAssertGreaterThan(bass, 0.1)
        XCTAssertLessThan(treble, bass * 0.01)
        XCTAssertEqual(musicResponse(60, style: .bass, coil: 3), bass, accuracy: 1e-4, "both grips")
    }

    func testFullRangeSplitsBassAndMidsAcrossGrips() {
        let leftBass = musicResponse(60, style: .fullRange, coil: 2)
        let rightBass = musicResponse(60, style: .fullRange, coil: 3)
        let rightMids = musicResponse(280, style: .fullRange, coil: 3)
        XCTAssertGreaterThan(leftBass, rightBass * 3)
        XCTAssertGreaterThan(rightMids, rightBass * 3)
    }

    func testFeedIsIgnoredUnlessStreaming() {
        for style in [nil, CoilMusicStyle.beats] {
            let mixer = VoiceCoilMixer()
            mixer.setMusic(style: style, gain: 1)
            sine(60, frames: 4_800).withUnsafeBufferPointer { mixer.feedMusic($0, sampleRate: 48_000) }
            mixer.setMusic(style: .bass, gain: 1)
            XCTAssertEqual(channel(render(mixer, frames: 2_048), 2).max(), 0)
        }
    }

    func testResamplerProducesTheOutputRate() {
        var resampler = LinearResampler()
        var out: [Float] = []
        var produced = 0
        let block = [Float](repeating: 1, count: 441)
        for _ in 0..<100 {
            block.withUnsafeBufferPointer { resampler.process($0, ratio: 44_100.0 / 48_000.0, into: &out) }
            produced += out.count
        }
        XCTAssertEqual(produced, 48_000, accuracy: 2, "one second in, one second out")
        XCTAssertTrue(out.allSatisfy { abs($0 - 1) < 1e-6 })
    }

    // MARK: - Music Sync routing

    func testCoilStyleFollowsTheMusicSettings() {
        var music = MusicSyncConfiguration()
        music.isEnabled = true
        music.hapticsStyle = .fullRange
        XCTAssertEqual(music.coilMusicStyle(coilsAvailable: true), .fullRange)
        XCTAssertNil(music.coilMusicStyle(coilsAvailable: false), "no USB: the motors keep the music")

        music.hapticsOnVoiceCoils = false
        XCTAssertNil(music.coilMusicStyle(coilsAvailable: true))

        music.hapticsOnVoiceCoils = true
        music.hapticsStyle = .beatPunch
        XCTAssertEqual(music.coilMusicStyle(coilsAvailable: true), .beats)
        music.hapticsStyle = .off
        XCTAssertNil(music.coilMusicStyle(coilsAvailable: true))
    }

    func testOlderSettingsDefaultToTheCoils() throws {
        let decoded = try JSONDecoder().decode(MusicSyncConfiguration.self, from: Data("{}".utf8))
        XCTAssertTrue(decoded.hapticsOnVoiceCoils)
        var config = MusicSyncConfiguration()
        config.hapticsOnVoiceCoils = false
        let roundTrip = try JSONDecoder().decode(MusicSyncConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertFalse(roundTrip.hapticsOnVoiceCoils)
    }

    // MARK: - Subwoofer

    private func subwooferResponse(_ hz: Float, settings: SubwooferSettings, coil: Int = 2) -> Float {
        let mixer = VoiceCoilMixer()
        mixer.setSubwoofer(settings)
        let block = 512, blocks = 40
        let input = sine(hz, frames: block * blocks)
        var out: [Float] = []
        for b in 0..<blocks {
            input[(b * block)..<((b + 1) * block)].withUnsafeBufferPointer {
                mixer.feedSubwoofer($0, sampleRate: 48_000)
            }
            out += channel(render(mixer, frames: block), coil)
        }
        return rms(out[(out.count / 2)...])
    }

    private let flatSub = SubwooferSettings(level: 0.4, crossoverHz: 120, boostDeepBass: false)

    /// Fourth-order low-pass: the bass passes, a vocal does not.
    func testSubwooferCrossover() {
        let bass = subwooferResponse(60, settings: flatSub)
        let voice = subwooferResponse(1_000, settings: flatSub)
        XCTAssertGreaterThan(bass, 0.1)
        XCTAssertLessThan(voice, bass * 0.002)
        XCTAssertEqual(subwooferResponse(60, settings: flatSub, coil: 3), bass, accuracy: 1e-4, "both grips")
    }

    /// Linear like a real subwoofer: half the music, half the drive.
    func testSubwooferFollowsTheMusicLevel() {
        let quiet = SubwooferSettings(level: 0.1, crossoverHz: 120, boostDeepBass: false)
        let louder = SubwooferSettings(level: 0.2, crossoverHz: 120, boostDeepBass: false)
        XCTAssertEqual(subwooferResponse(60, settings: louder) / subwooferResponse(60, settings: quiet), 2, accuracy: 0.05)
    }

    func testCrossoverSettingMovesTheCutoff() {
        let low = SubwooferSettings(level: 0.4, crossoverHz: 60, boostDeepBass: false)
        let high = SubwooferSettings(level: 0.4, crossoverHz: 200, boostDeepBass: false)
        XCTAssertGreaterThan(subwooferResponse(150, settings: high), subwooferResponse(150, settings: low) * 4)
    }

    /// Amplitude of `hz` in the settled half of a coil's output.
    private func subwooferComponent(_ hz: Float, playing input: Float, settings: SubwooferSettings) -> Float {
        let mixer = VoiceCoilMixer()
        mixer.setSubwoofer(settings)
        let block = 512, blocks = 40
        let signal = sine(input, frames: block * blocks)
        var out: [Float] = []
        for b in 0..<blocks {
            signal[(b * block)..<((b + 1) * block)].withUnsafeBufferPointer {
                mixer.feedSubwoofer($0, sampleRate: 48_000)
            }
            out += channel(render(mixer, frames: block), 2)
        }
        // Hann-windowed so a fundamental that does not fit the window a whole
        // number of times cannot leak into the octave's bin.
        let settled = Array(out[(out.count / 2)...])
        let count = Float(settled.count)
        var re: Float = 0, im: Float = 0, windowSum: Float = 0
        for (n, x) in settled.enumerated() {
            let window = 0.5 - 0.5 * cosf(2 * Float.pi * Float(n) / (count - 1))
            let phase = 2 * Float.pi * hz * Float(n) / 48_000
            re += window * x * cosf(phase)
            im += window * x * sinf(phase)
            windowSum += window
        }
        return 2 * (re * re + im * im).squareRoot() / windowSum
    }

    /// A note too deep for the coils gains its octave, which they can move;
    /// without the boost there is none.
    func testDeepBassBoostAddsTheOctave() {
        var boosted = flatSub
        boosted.boostDeepBass = true
        let fundamental = subwooferComponent(35, playing: 35, settings: boosted)
        XCTAssertLessThan(subwooferComponent(70, playing: 35, settings: flatSub), fundamental * 0.02)
        XCTAssertGreaterThan(subwooferComponent(70, playing: 35, settings: boosted), fundamental * 0.3)
    }

    func testSubwooferOffIgnoresTheFeed() {
        let mixer = VoiceCoilMixer()
        sine(60, frames: 4_800).withUnsafeBufferPointer { mixer.feedSubwoofer($0, sampleRate: 48_000) }
        XCTAssertEqual(channel(render(mixer, frames: 2_048), 2).max(), 0)
    }

    func testSubwooferSettingsDecodeAndClamp() throws {
        let empty = try JSONDecoder().decode(SubwooferConfiguration.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, SubwooferConfiguration())
        XCTAssertFalse(empty.isEnabled)

        let wild = #"{"isEnabled": true, "level": 3, "crossoverHz": 5000, "boostDeepBass": false}"#
        let clamped = try JSONDecoder().decode(SubwooferConfiguration.self, from: Data(wild.utf8))
        XCTAssertEqual(clamped.level, 1)
        XCTAssertEqual(clamped.crossoverHz, SubwooferConfiguration.crossoverRange.upperBound)
        XCTAssertFalse(clamped.boostDeepBass)

        let session = try JSONDecoder().decode(SessionSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(session.subwoofer, SubwooferConfiguration())
    }

    // MARK: - Handover from the rumble emulation

    private func flag0(audioHaptics: Bool, layout: DSOutputLayout, v2: Bool = false) -> UInt8 {
        HIDDriver.buildOutputReport(
            layout: layout, useVibrationV2: v2, lightbar: AppColor(red: 0, green: 0, blue: 0),
            playerLEDMask: 0, playerBrightness: .medium, micLED: .off,
            leftMotor: 0, rightMotor: 0,
            leftTrigger: SingleTriggerConfig(), rightTrigger: SingleTriggerConfig(),
            audioHaptics: audioHaptics
        )[layout.validFlag0]
    }

    /// With the bit set the firmware ignores the haptic audio channels, so
    /// it has to drop while the coils play — and only then.
    func testCoilsTakeTheActuatorsFromTheRumbleEmulation() {
        for layout in [DSOutputLayout.usb, DSOutputLayout.bluetooth] {
            XCTAssertNotEqual(flag0(audioHaptics: false, layout: layout) & DualSenseProtocol.ValidFlag0.hapticsSelect, 0)
            let coils = flag0(audioHaptics: true, layout: layout)
            XCTAssertEqual(coils & DualSenseProtocol.ValidFlag0.hapticsSelect, 0)
            XCTAssertNotEqual(coils & DualSenseProtocol.ValidFlag0.rightTriggerMotorEnable, 0, "triggers keep working")
            XCTAssertNotEqual(coils & DualSenseProtocol.ValidFlag0.leftTriggerMotorEnable, 0, "triggers keep working")
        }
    }
}
