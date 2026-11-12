import XCTest
@testable import SingleSense

/// The five-lamp indicator row, both as a player number and as an audio meter.
final class PlayerLEDTests: XCTestCase {

    /// `player_ids[]` from `dualsense_set_player_leds`, centred across the row
    /// the way the console numbers players.
    func testPatternsMatchTheKernel() {
        XCTAssertEqual(PlayerLEDMode.off.bitmask, 0)
        XCTAssertEqual(PlayerLEDMode.player1.bitmask, 1 << 2)
        XCTAssertEqual(PlayerLEDMode.player2.bitmask, (1 << 3) | (1 << 1))
        XCTAssertEqual(PlayerLEDMode.player3.bitmask, (1 << 4) | (1 << 2) | (1 << 0))
        XCTAssertEqual(PlayerLEDMode.player4.bitmask, (1 << 4) | (1 << 3) | (1 << 1) | (1 << 0))
        XCTAssertEqual(PlayerLEDMode.player5.bitmask, 0x1F)
    }

    /// A light bar that is emphatically *not* in the old Music Sync mode: the
    /// audio styles must reach the row through the Music Sync switch alone.
    private func lightbar(_ mode: LightingMode = .rainbow) -> LightbarConfiguration {
        var c = LightbarConfiguration()
        c.mode = mode
        c.playerLEDMode = .player1
        return c
    }

    private func music(_ style: PlayerLEDAudioStyle, enabled: Bool = true) -> MusicSyncConfiguration {
        var m = MusicSyncConfiguration()
        m.isEnabled = enabled
        m.playerLEDStyle = style
        return m
    }

    private func mask(_ style: PlayerLEDAudioStyle, level: Float, beat: Float = 0) -> UInt8 {
        lightbar().playerLEDMask(music: music(style), level: level, beat: beat)
    }

    func testVUMeterFillsFromTheLeft() {
        XCTAssertEqual(mask(.vuMeter, level: 0.0), 0x00)
        XCTAssertEqual(mask(.vuMeter, level: 0.1), 0x01)
        XCTAssertEqual(mask(.vuMeter, level: 0.5), 0x07)
        XCTAssertEqual(mask(.vuMeter, level: 1.0), 0x1F)
    }

    /// The spread reuses the console's own centred progression.
    func testCenterSpreadGrowsOutward() {
        XCTAssertEqual(mask(.centerSpread, level: 0.0), 0x00)
        XCTAssertEqual(mask(.centerSpread, level: 0.1), PlayerLEDMode.player1.bitmask)
        XCTAssertEqual(mask(.centerSpread, level: 0.3), PlayerLEDMode.player2.bitmask)
        XCTAssertEqual(mask(.centerSpread, level: 0.5), PlayerLEDMode.player3.bitmask)
        XCTAssertEqual(mask(.centerSpread, level: 1.0), PlayerLEDMode.player5.bitmask)
    }

    func testBeatPulseIgnoresLevel() {
        XCTAssertEqual(mask(.beatPulse, level: 1.0, beat: 0.0), 0x00)
        XCTAssertEqual(mask(.beatPulse, level: 0.0, beat: 1.0), 0x1F)
    }

    func testKickAndSnareUseDifferentPairsAndGoDarkBetweenHits() {
        let m = music(.kickSnare)
        XCTAssertEqual(m.playerLEDMask(level: 1, beat: 1, kick: 0, snare: 0), 0x00)
        XCTAssertEqual(m.playerLEDMask(level: 1, beat: 1, kick: 1, snare: 0), 0x03)
        XCTAssertEqual(m.playerLEDMask(level: 1, beat: 1, kick: 0, snare: 1), 0x18)
        XCTAssertEqual(m.playerLEDMask(level: 1, beat: 1, kick: 1, snare: 1), 0x1B)
    }

    func testAudioStylesNeedMusicSyncSwitchedOn() {
        let c = lightbar()
        XCTAssertEqual(
            c.playerLEDMask(music: music(.vuMeter, enabled: false), level: 1.0, beat: 1.0),
            PlayerLEDMode.player1.bitmask
        )
    }

    /// The whole point of the split: the row follows the music whatever the
    /// light bar happens to be doing, and it used to require the Music Sync
    /// lighting mode.
    func testTheRowFollowsTheMusicInEveryLightingMode() {
        for mode in LightingMode.selectable {
            XCTAssertEqual(
                lightbar(mode).playerLEDMask(music: music(.vuMeter), level: 1.0),
                0x1F,
                "\(mode.rawValue) must not stop the indicator row from following the music"
            )
        }
    }

    func testFixedStyleKeepsTheChosenPlayerPattern() {
        let c = lightbar()
        XCTAssertEqual(
            c.playerLEDMask(music: music(.fixed), level: 1.0, beat: 1.0),
            PlayerLEDMode.player1.bitmask
        )
    }

    func testOffBrightnessDarkensTheRowRegardless() {
        var c = lightbar()
        c.playerLEDBrightness = .off
        XCTAssertEqual(c.playerLEDMask(music: music(.vuMeter), level: 1.0, beat: 1.0), 0)
    }

    func testHostileLevelsProduceNoLamps() {
        XCTAssertEqual(mask(.centerSpread, level: .nan, beat: .nan), 0)
        XCTAssertEqual(mask(.centerSpread, level: -5), 0)
        XCTAssertEqual(mask(.centerSpread, level: 9), 0x1F)
    }
}

/// Rumble driven by the music.
final class MusicHapticsTests: XCTestCase {

    private func config(_ style: MusicHapticsStyle, intensity: Double = 1.0) -> MusicSyncConfiguration {
        var m = MusicSyncConfiguration()
        m.isEnabled = true
        m.hapticsStyle = style
        m.hapticsIntensity = intensity
        return m
    }

    /// The motors stall below a threshold, so an audible signal must start
    /// above it rather than ramping up from a dead zone.
    func testMotorCurveGatesAndFloors() {
        XCTAssertEqual(RumbleCurve.shape(0), 0)
        XCTAssertEqual(RumbleCurve.shape(RumbleCurve.gate), 0)
        XCTAssertGreaterThanOrEqual(RumbleCurve.shape(RumbleCurve.gate + 0.01), RumbleCurve.floor)
        XCTAssertEqual(RumbleCurve.shape(1), 1, accuracy: 0.001)
        XCTAssertEqual(RumbleCurve.shape(.nan), 0)
    }

    func testBassKickUsesOnlyTheHeavyMotor() {
        let motors = config(.bassKick).rumble(bass: 1, mid: 1, treble: 1, beat: 0)
        XCTAssertEqual(motors.left, 1, accuracy: 0.001)
        XCTAssertEqual(motors.right, 0)
    }

    /// The two motors have different characters; mapping both to the same
    /// signal is what makes rumble read as undifferentiated buzzing.
    func testFullRangeSplitsBassAndTreble() {
        let c = config(.fullRange)
        let bassOnly = c.rumble(bass: 1, mid: 0, treble: 0, beat: 0)
        XCTAssertEqual(bassOnly.left, 1, accuracy: 0.001)
        XCTAssertEqual(bassOnly.right, 0)

        let trebleOnly = c.rumble(bass: 0, mid: 0, treble: 1, beat: 0)
        XCTAssertEqual(trebleOnly.left, 0)
        XCTAssertEqual(trebleOnly.right, 1, accuracy: 0.001)

        // Mids ride the light motor at half weight so vocals do not drown out
        // the cymbals it conveys well.
        let midOnly = c.rumble(bass: 0, mid: 1, treble: 0, beat: 0)
        XCTAssertEqual(midOnly.right, RumbleCurve.shape(0.5), accuracy: 0.001)
    }

    func testBeatPunchFollowsOnsetsNotLevel() {
        let c = config(.beatPunch)
        XCTAssertEqual(c.rumble(bass: 1, mid: 1, treble: 1, beat: 0).left, 0)
        XCTAssertEqual(c.rumble(bass: 0, mid: 0, treble: 0, beat: 1).left, 1, accuracy: 0.001)
    }

    func testMotorsAreSilentWheneverTheyShouldBe() {
        let full: (MusicSyncConfiguration) -> (left: Float, right: Float) = {
            $0.rumble(bass: 1, mid: 1, treble: 1, beat: 1)
        }
        XCTAssertEqual(full(config(.off)).left, 0)

        var switchedOff = config(.fullRange)
        switchedOff.isEnabled = false
        XCTAssertEqual(full(switchedOff).left, 0)

        XCTAssertEqual(full(config(.fullRange, intensity: 0)).left, 0)

        let hostile = config(.fullRange).rumble(bass: .nan, mid: .nan, treble: .nan, beat: .nan)
        XCTAssertEqual(hostile.left, 0)
        XCTAssertEqual(hostile.right, 0)
    }

    /// The intensity slider is a ceiling on the motors, not a fixed level: the
    /// music is what decides how much of it gets used.
    func testIntensityIsACeilingTheMusicRidesUnder() {
        let c = config(.fullRange, intensity: 0.5)
        let loud = c.rumble(bass: 1, mid: 0, treble: 1, beat: 0)
        XCTAssertEqual(loud.left, 0.5, accuracy: 0.001)
        XCTAssertEqual(loud.right, 0.5, accuracy: 0.001)

        let quiet = c.rumble(bass: 0.3, mid: 0, treble: 0.3, beat: 0)
        XCTAssertLessThan(quiet.left, loud.left)
        XCTAssertGreaterThan(quiet.left, 0)
    }

    /// Which parts of the controller the music drives, which is what the new
    /// section switches on and off.
    func testChannelsAreIndependent() {
        var m = MusicSyncConfiguration()
        m.isEnabled = true
        m.drivesLightbar = false
        m.playerLEDStyle = .fixed
        m.hapticsStyle = .off
        XCTAssertFalse(m.isDrivingLightbar)
        XCTAssertFalse(m.isDrivingPlayerLEDs)
        XCTAssertFalse(m.isDrivingRumble)
        XCTAssertTrue(m.needsAudioCapture, "the meters still need the tap open")

        m.drivesLightbar = true
        m.playerLEDStyle = .vuMeter
        m.hapticsStyle = .bassKick
        XCTAssertTrue(m.isDrivingLightbar)
        XCTAssertTrue(m.isDrivingPlayerLEDs)
        XCTAssertTrue(m.isDrivingRumble)

        m.isEnabled = false
        XCTAssertFalse(m.isDrivingLightbar)
        XCTAssertFalse(m.isDrivingPlayerLEDs)
        XCTAssertFalse(m.isDrivingRumble)
        XCTAssertFalse(m.needsAudioCapture)
    }

    /// The indicator row and the motor bytes ride in the same report as the
    /// light bar colour. A static bar skips its frame to avoid streaming 60
    /// identical packets a second — which would freeze them mid-track.
    func testDrivingOnlyTheLEDsOrTheMotorsStillNeedsEveryFrame() {
        var m = MusicSyncConfiguration()
        m.isEnabled = true
        m.drivesLightbar = false
        m.playerLEDStyle = .fixed
        m.hapticsStyle = .off
        XCTAssertFalse(m.needsContinuousOutput, "nothing on the controller is following the music")

        m.playerLEDStyle = .vuMeter
        XCTAssertTrue(m.needsContinuousOutput, "the row has to be refreshed even from a static bar")

        m.playerLEDStyle = .fixed
        m.hapticsStyle = .bassKick
        XCTAssertTrue(m.needsContinuousOutput, "so do the motors")

        m.hapticsStyle = .off
        m.drivesLightbar = true
        XCTAssertTrue(m.needsContinuousOutput)
    }
}

/// Per-band automatic gain control.
final class BandNormalizerTests: XCTestCase {

    /// Music falls off steeply with frequency. Normalising every band against
    /// one shared peak pins treble near zero — which left the right rumble
    /// motor and the blue channel permanently idle.
    func testEveryBandBecomesUsableDespiteSpectralTilt() {
        var normalizer = BandNormalizer()
        var levels = AudioLevels.silent
        // Treble roughly 31 dB below bass, unremarkable for real material.
        for _ in 0..<400 {
            levels = normalizer.normalize(bass: 0.30, mid: 0.06, treble: 0.008, gain: 1)
        }
        XCTAssertGreaterThan(levels.bass, 0.5)
        XCTAssertGreaterThan(levels.mid, 0.5)
        XCTAssertGreaterThan(levels.treble, 0.5, "treble must reach the right motor")
        XCTAssertGreaterThan(levels.overall, 0.5)
    }

    func testDigitalSilenceStaysSilent() {
        var normalizer = BandNormalizer()
        var levels = AudioLevels.silent
        for _ in 0..<2000 { levels = normalizer.normalize(bass: 0, mid: 0, treble: 0, gain: 1) }
        XCTAssertEqual(levels, .silent)
    }

    /// With the references decaying, a noise floor must not be amplified into
    /// a full-scale reading.
    func testNoiseFloorIsNotAmplified() {
        var normalizer = BandNormalizer()
        var levels = AudioLevels.silent
        for _ in 0..<2000 { levels = normalizer.normalize(bass: 1e-6, mid: 1e-6, treble: 1e-6, gain: 1) }
        XCTAssertEqual(levels, .silent)
    }

    func testAnExtremelyQuietBandIsCappedByTheRelativeFloor() {
        var normalizer = BandNormalizer()
        var levels = AudioLevels.silent
        for _ in 0..<2000 { levels = normalizer.normalize(bass: 0.5, mid: 0.5, treble: 0.0005, gain: 1) }
        XCTAssertLessThan(levels.treble, 0.95)
    }

    /// The gain used to cancel out of the ratio, making the slider a no-op.
    func testSensitivityChangesTheOutput() {
        var quiet = BandNormalizer()
        var loud = BandNormalizer()
        var quietLevels = AudioLevels.silent
        var loudLevels = AudioLevels.silent
        for _ in 0..<400 {
            quietLevels = quiet.normalize(bass: 0.3, mid: 0.06, treble: 0.008, gain: 0.4)
            loudLevels = loud.normalize(bass: 0.3, mid: 0.06, treble: 0.008, gain: 1.0)
        }
        XCTAssertGreaterThan(loudLevels.overall - quietLevels.overall, 0.05)
    }

    func testNonFiniteInputIsRejected() {
        var normalizer = BandNormalizer()
        let levels = normalizer.normalize(bass: .nan, mid: .infinity, treble: -1, gain: 1)
        XCTAssertTrue(levels.bass.isFinite)
        XCTAssertTrue(levels.mid.isFinite)
        XCTAssertTrue(levels.treble.isFinite)
    }
}

final class RollingDynamicsNormalizerTests: XCTestCase {
    func testSustainedBassBecomesTheFloorAndKicksRiseAboveIt() {
        var normalizer = RollingDynamicsNormalizer()
        for _ in 0..<96 {
            XCTAssertEqual(normalizer.normalize(0.10, gain: 1), 0, accuracy: 0.001)
        }
        XCTAssertEqual(normalizer.normalize(0.20, gain: 1), 1, accuracy: 0.001)
        XCTAssertEqual(normalizer.normalize(0.10, gain: 1), 0, accuracy: 0.001)
        XCTAssertEqual(normalizer.normalize(0.16, gain: 1), powf(0.6, 0.7), accuracy: 0.001)
    }

    func testFloorAdaptsWhenTheSongChangesLevel() {
        var normalizer = RollingDynamicsNormalizer()
        for _ in 0..<96 { _ = normalizer.normalize(0.10, gain: 1) }
        for _ in 0..<96 { _ = normalizer.normalize(0.15, gain: 1) }
        XCTAssertEqual(normalizer.normalize(0.15, gain: 1), 0, accuracy: 0.001)
        XCTAssertGreaterThan(normalizer.normalize(0.22, gain: 1), 0.5)
    }

    func testNearlyFlatBassIsNotAmplifiedIntoAFullKick() {
        var normalizer = RollingDynamicsNormalizer()
        for _ in 0..<96 { _ = normalizer.normalize(0.10, gain: 1) }
        XCTAssertLessThan(normalizer.normalize(0.102, gain: 1), 0.3)
        normalizer.reset()
        XCTAssertEqual(normalizer.normalize(0.10, gain: 1), 0)
    }
}

final class PercussiveOnsetDetectorTests: XCTestCase {
    func testRapidAlternatingKicksAndSnaresRemainDistinct() {
        var detector = PercussiveOnsetDetector()
        let step = 512.0 / 48_000.0
        var detected: [Double] = []

        for frame in 0..<300 {
            let time = Double(frame) * step
            // Alternate kick and snare roughly every 100 ms over a loud bass
            // line. Normalised levels can remain near one the whole time.
            let kick = frame % 19 == 0
            let snare = frame % 19 == 9
            let hits = detector.detect(
                bass: kick ? 0.30 : 0.08,
                mid: snare ? 0.18 : 0.04,
                treble: snare ? 0.06 : 0.008,
                at: time
            )
            if hits.kick || hits.snare { detected.append(time) }
        }

        XCTAssertEqual(detected.count, 31, "the first window primes the baseline")
    }

    func testSustainedBassAndQuietNoiseDoNotRetrigger() {
        var detector = PercussiveOnsetDetector()
        let step = 512.0 / 48_000.0
        var sustainedHits = 0
        for frame in 0..<300 {
            let hits = detector.detect(bass: 0.08, mid: 0.04, treble: 0.008, at: Double(frame) * step)
            if hits.kick || hits.snare {
                sustainedHits += 1
            }
        }
        XCTAssertEqual(sustainedHits, 0)

        detector.reset()
        for frame in 0..<300 {
            XCTAssertEqual(detector.detect(bass: 0.001, mid: 0.001, treble: 0.001, at: Double(frame) * step), .none)
        }
    }

    func testAHiHatOrMidOnlyAttackIsNotASnare() {
        var detector = PercussiveOnsetDetector()
        _ = detector.detect(bass: 0.001, mid: 0.02, treble: 0.006, at: 0)
        XCTAssertEqual(detector.detect(bass: 0.001, mid: 0.02, treble: 0.08, at: 0.2), .none)
        XCTAssertEqual(detector.detect(bass: 0.001, mid: 0.12, treble: 0.006, at: 0.4), .none)
        XCTAssertEqual(detector.detect(bass: 0.001, mid: 0.02, treble: 0.006, at: 0.5), .none)
        XCTAssertEqual(detector.detect(bass: 0.001, mid: 0.12, treble: 0.08, at: 0.6), PercussiveHits(snare: true))
    }

    func testRefractoryPeriodRejectsDoubleHitsAndResetAllowsRestart() {
        var detector = PercussiveOnsetDetector()
        _ = detector.detect(bass: 0.02, mid: 0, treble: 0, at: 0)
        XCTAssertEqual(detector.detect(bass: 0.3, mid: 0, treble: 0, at: 1.0), PercussiveHits(kick: true))
        XCTAssertEqual(detector.detect(bass: 0.02, mid: 0, treble: 0, at: 1.01), .none)
        XCTAssertEqual(detector.detect(bass: 0.3, mid: 0, treble: 0, at: 1.05), .none)
        detector.reset()
        _ = detector.detect(bass: 0.02, mid: 0, treble: 0, at: 0)
        XCTAssertEqual(detector.detect(bass: 0.3, mid: 0, treble: 0, at: 0.2), PercussiveHits(kick: true))
    }

    func testOrdinaryBassFluctuationDoesNotBecomeContinuousBeat() {
        var detector = PercussiveOnsetDetector()
        for frame in 0..<300 {
            let bass: Float = frame % 8 < 4 ? 0.08 : 0.13
            XCTAssertEqual(
                detector.detect(bass: bass, mid: 0.04, treble: 0.008, at: Double(frame) * 512 / 48_000),
                .none
            )
        }
    }
}
