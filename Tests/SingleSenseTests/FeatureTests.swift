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

    private func config(_ style: PlayerLEDAudioStyle) -> LightbarConfiguration {
        var c = LightbarConfiguration()
        c.mode = .musicSync
        c.playerLEDMode = .player1
        c.playerLEDAudioStyle = style
        return c
    }

    func testVUMeterFillsFromTheLeft() {
        let c = config(.vuMeter)
        XCTAssertEqual(c.playerLEDMask(level: 0.0, beat: 0), 0x00)
        XCTAssertEqual(c.playerLEDMask(level: 0.1, beat: 0), 0x01)
        XCTAssertEqual(c.playerLEDMask(level: 0.5, beat: 0), 0x07)
        XCTAssertEqual(c.playerLEDMask(level: 1.0, beat: 0), 0x1F)
    }

    /// The spread reuses the console's own centred progression.
    func testCenterSpreadGrowsOutward() {
        let c = config(.centerSpread)
        XCTAssertEqual(c.playerLEDMask(level: 0.0, beat: 0), 0x00)
        XCTAssertEqual(c.playerLEDMask(level: 0.1, beat: 0), PlayerLEDMode.player1.bitmask)
        XCTAssertEqual(c.playerLEDMask(level: 0.3, beat: 0), PlayerLEDMode.player2.bitmask)
        XCTAssertEqual(c.playerLEDMask(level: 0.5, beat: 0), PlayerLEDMode.player3.bitmask)
        XCTAssertEqual(c.playerLEDMask(level: 1.0, beat: 0), PlayerLEDMode.player5.bitmask)
    }

    func testBeatPulseIgnoresLevel() {
        let c = config(.beatPulse)
        XCTAssertEqual(c.playerLEDMask(level: 1.0, beat: 0.0), 0x00)
        XCTAssertEqual(c.playerLEDMask(level: 0.0, beat: 1.0), 0x1F)
    }

    func testAudioStylesOnlyApplyInMusicSync() {
        var c = config(.vuMeter)
        c.mode = .rainbow
        XCTAssertEqual(c.playerLEDMask(level: 1.0, beat: 1.0), PlayerLEDMode.player1.bitmask)
    }

    func testOffBrightnessDarkensTheRowRegardless() {
        var c = config(.vuMeter)
        c.playerLEDBrightness = .off
        XCTAssertEqual(c.playerLEDMask(level: 1.0, beat: 1.0), 0)
    }

    func testHostileLevelsProduceNoLamps() {
        let c = config(.centerSpread)
        XCTAssertEqual(c.playerLEDMask(level: .nan, beat: .nan), 0)
        XCTAssertEqual(c.playerLEDMask(level: -5, beat: 0), 0)
        XCTAssertEqual(c.playerLEDMask(level: 9, beat: 0), 0x1F)
    }
}

/// Rumble driven by the music.
final class MusicHapticsTests: XCTestCase {

    private func config(_ style: MusicHapticsStyle, intensity: Double = 1.0) -> LightbarConfiguration {
        var c = LightbarConfiguration()
        c.mode = .musicSync
        c.musicHapticsStyle = style
        c.musicHapticsIntensity = intensity
        return c
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
        let motors = config(.bassKick).musicRumble(bass: 1, mid: 1, treble: 1, beat: 0)
        XCTAssertEqual(motors.left, 1, accuracy: 0.001)
        XCTAssertEqual(motors.right, 0)
    }

    /// The two motors have different characters; mapping both to the same
    /// signal is what makes rumble read as undifferentiated buzzing.
    func testFullRangeSplitsBassAndTreble() {
        let c = config(.fullRange)
        let bassOnly = c.musicRumble(bass: 1, mid: 0, treble: 0, beat: 0)
        XCTAssertEqual(bassOnly.left, 1, accuracy: 0.001)
        XCTAssertEqual(bassOnly.right, 0)

        let trebleOnly = c.musicRumble(bass: 0, mid: 0, treble: 1, beat: 0)
        XCTAssertEqual(trebleOnly.left, 0)
        XCTAssertEqual(trebleOnly.right, 1, accuracy: 0.001)

        // Mids ride the light motor at half weight so vocals do not drown out
        // the cymbals it conveys well.
        let midOnly = c.musicRumble(bass: 0, mid: 1, treble: 0, beat: 0)
        XCTAssertEqual(midOnly.right, RumbleCurve.shape(0.5), accuracy: 0.001)
    }

    func testBeatPunchFollowsOnsetsNotLevel() {
        let c = config(.beatPunch)
        XCTAssertEqual(c.musicRumble(bass: 1, mid: 1, treble: 1, beat: 0).left, 0)
        XCTAssertEqual(c.musicRumble(bass: 0, mid: 0, treble: 0, beat: 1).left, 1, accuracy: 0.001)
    }

    func testMotorsAreSilentWheneverTheyShouldBe() {
        let full: (LightbarConfiguration) -> (left: Float, right: Float) = {
            $0.musicRumble(bass: 1, mid: 1, treble: 1, beat: 1)
        }
        XCTAssertEqual(full(config(.off)).left, 0)

        var notMusic = config(.fullRange)
        notMusic.mode = .rainbow
        XCTAssertEqual(full(notMusic).left, 0)

        XCTAssertEqual(full(config(.fullRange, intensity: 0)).left, 0)

        let hostile = config(.fullRange).musicRumble(bass: .nan, mid: .nan, treble: .nan, beat: .nan)
        XCTAssertEqual(hostile.left, 0)
        XCTAssertEqual(hostile.right, 0)
    }

    func testIntensityScalesOutput() {
        let half = config(.fullRange, intensity: 0.5)
            .musicRumble(bass: 1, mid: 0, treble: 1, beat: 0)
        XCTAssertEqual(half.left, 0.5, accuracy: 0.001)
        XCTAssertEqual(half.right, 0.5, accuracy: 0.001)
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
