import Foundation

/// Everything Music Sync needs, independent of the lighting mode.
///
/// Music Sync used to be one of the `LightingMode` cases, which made it
/// mutually exclusive with static colour, rainbow and the rest — even though
/// it drives the player indicator row and the rumble motors as well as the
/// light bar. Keeping it separate lets the music drive any subset of the three
/// while the light bar stays on whatever mode the user picked.
public struct MusicSyncConfiguration: Codable, Equatable {
    /// Master switch. Nothing is analysed, and the audio tap stays closed,
    /// while this is off.
    public var isEnabled: Bool = false

    /// Whether the music takes over the light bar from the lighting mode.
    public var drivesLightbar: Bool = true
    public var lightbarStyle: MusicSyncStyle = .spectrum

    /// `.fixed` leaves the indicator row on the pattern chosen in Lightbar.
    public var playerLEDStyle: PlayerLEDAudioStyle = .centerSpread

    /// Off by default: continuous rumble is intrusive and eats the battery, so
    /// it is something the user opts into rather than out of.
    public var hapticsStyle: MusicHapticsStyle = .off
    /// Ceiling for the motors; the music decides how much of it is used.
    public var hapticsIntensity: Double = 0.6
    /// Over USB, send the music itself to the voice coils in the grips
    /// instead of turning it into motor levels.
    public var hapticsOnVoiceCoils: Bool = true

    public var sensitivity: Double = 1.0        // 0.25 ... 4.0
    public var smoothing: Double = 0.35         // 0.0 (snappy) ... 1.0 (damped)
    public var minimumBrightness: Double = 0.05

    public init() {}

    // MARK: - What the music is actually driving

    public var isDrivingLightbar: Bool { isEnabled && drivesLightbar }
    public var isDrivingPlayerLEDs: Bool { isEnabled && playerLEDStyle != .fixed }
    public var isDrivingRumble: Bool { isEnabled && hapticsStyle != .off && hapticsIntensity > 0 }

    /// What the coils should play, given whether they can be reached. Nil
    /// leaves the haptics to the motors.
    public func coilMusicStyle(coilsAvailable: Bool) -> CoilMusicStyle? {
        guard isDrivingRumble, hapticsOnVoiceCoils, coilsAvailable else { return nil }
        return CoilMusicStyle(hapticsStyle)
    }

    /// True when the analysis is worth its CPU: the tap only needs to be open
    /// while something is listening to it.
    public var needsAudioCapture: Bool { isEnabled }

    /// True when the hardware has to be re-sent every frame.
    ///
    /// A static light bar is normally left alone rather than streamed at 60
    /// packets a second, but the indicator row and the motors travel in that
    /// same report — so skipping the frame would freeze them mid-track.
    public var needsContinuousOutput: Bool {
        isDrivingLightbar || isDrivingPlayerLEDs || isDrivingRumble
    }

    // MARK: - Resolution

    /// Resolves the two rumble motors from the audio analysis.
    /// Returns silence unless the music is driving the motors.
    ///
    /// The two motors are not interchangeable: the left one is a heavy
    /// low-frequency weight, the right a lighter, faster one. Mapping bass to
    /// the left and the upper bands to the right is what makes the effect read
    /// as the music rather than as undifferentiated buzzing.
    public func rumble(bass: Float, mid: Float, treble: Float, beat: Float) -> (left: Float, right: Float) {
        guard isDrivingRumble else { return (0, 0) }
        let gain = Float(hapticsIntensity.isFinite ? min(max(hapticsIntensity, 0), 1) : 0)
        guard gain > 0 else { return (0, 0) }

        switch hapticsStyle {
        case .off:
            return (0, 0)
        case .bassKick:
            return (RumbleCurve.shape(bass) * gain, 0)
        case .fullRange:
            // Mids are folded in at half weight so vocals do not drown out
            // the cymbals and hats the light motor is good at conveying.
            let highs = max(treble, mid * 0.5)
            return (RumbleCurve.shape(bass) * gain, RumbleCurve.shape(highs) * gain)
        case .beatPunch:
            return (RumbleCurve.shape(beat) * gain, 0)
        }
    }

    /// The indicator row the music is asking for, or nil when the row is not
    /// music-driven and should keep its fixed pattern.
    public func playerLEDMask(level: Float, beat: Float) -> UInt8? {
        guard isDrivingPlayerLEDs else { return nil }

        switch playerLEDStyle {
        case .fixed:
            return nil
        case .vuMeter:
            return PlayerLEDIndicator.bar(lampsLit: PlayerLEDIndicator.lamps(for: level))
        case .centerSpread:
            return PlayerLEDIndicator.centredPatterns[PlayerLEDIndicator.lamps(for: level)]
        case .beatPulse:
            return beat > 0.35 ? 0x1F : 0x00
        }
    }

    // MARK: - Codable

    /// Decoding tolerates a file written by an older build, or a hand-edited
    /// one, by falling back per field rather than discarding the whole thing.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = MusicSyncConfiguration()
        isEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? fallback.isEnabled
        drivesLightbar = (try? container.decodeIfPresent(Bool.self, forKey: .drivesLightbar)) ?? fallback.drivesLightbar
        lightbarStyle = (try? container.decodeIfPresent(MusicSyncStyle.self, forKey: .lightbarStyle)) ?? fallback.lightbarStyle
        playerLEDStyle = (try? container.decodeIfPresent(PlayerLEDAudioStyle.self, forKey: .playerLEDStyle)) ?? fallback.playerLEDStyle
        hapticsStyle = (try? container.decodeIfPresent(MusicHapticsStyle.self, forKey: .hapticsStyle)) ?? fallback.hapticsStyle
        hapticsIntensity = Self.clamped(
            try? container.decodeIfPresent(Double.self, forKey: .hapticsIntensity),
            0...1, fallback.hapticsIntensity
        )
        hapticsOnVoiceCoils = (try? container.decodeIfPresent(Bool.self, forKey: .hapticsOnVoiceCoils)) ?? fallback.hapticsOnVoiceCoils
        sensitivity = Self.clamped(
            try? container.decodeIfPresent(Double.self, forKey: .sensitivity),
            0.25...4.0, fallback.sensitivity
        )
        smoothing = Self.clamped(
            try? container.decodeIfPresent(Double.self, forKey: .smoothing),
            0...1, fallback.smoothing
        )
        minimumBrightness = Self.clamped(
            try? container.decodeIfPresent(Double.self, forKey: .minimumBrightness),
            0...0.5, fallback.minimumBrightness
        )
    }

    private static func clamped(_ value: Double??, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        guard let value = value ?? nil, value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - Migration

extension MusicSyncConfiguration {
    /// The Music Sync settings as they were stored — on `LightbarConfiguration`,
    /// with the feature expressed as `mode == .musicSync`.
    ///
    /// Read from the *same* `lightbar` object in an older session or profile
    /// file, so a saved setup keeps working across the split.
    struct Legacy {
        var wasActive = false
        var lightbarStyle: MusicSyncStyle?
        var playerLEDStyle: PlayerLEDAudioStyle?
        var hapticsStyle: MusicHapticsStyle?
        var hapticsIntensity: Double?
        var sensitivity: Double?
        var smoothing: Double?
        var minimumBrightness: Double?
    }

    /// Rebuilds the configuration from a pre-split file. `isEnabled` can only
    /// come from the old lighting mode: every other legacy key was written
    /// with a default value whether or not the feature was ever used.
    static func migrated(from legacy: Legacy) -> MusicSyncConfiguration {
        var config = MusicSyncConfiguration()
        config.isEnabled = legacy.wasActive
        config.drivesLightbar = true
        if let style = legacy.lightbarStyle { config.lightbarStyle = style }
        if let style = legacy.playerLEDStyle { config.playerLEDStyle = style }
        if let style = legacy.hapticsStyle { config.hapticsStyle = style }
        if let value = legacy.hapticsIntensity { config.hapticsIntensity = clamped(value, 0...1, config.hapticsIntensity) }
        if let value = legacy.sensitivity { config.sensitivity = clamped(value, 0.25...4.0, config.sensitivity) }
        if let value = legacy.smoothing { config.smoothing = clamped(value, 0...1, config.smoothing) }
        if let value = legacy.minimumBrightness { config.minimumBrightness = clamped(value, 0...0.5, config.minimumBrightness) }
        return config
    }
}

extension MusicSyncConfiguration.Legacy: Decodable {
    private enum CodingKeys: String, CodingKey {
        case mode
        case musicSyncStyle
        case playerLEDAudioStyle
        case musicHapticsStyle
        case musicHapticsIntensity
        case audioSensitivity
        case audioSmoothing
        case audioMinimumBrightness
    }

    /// Every field is read defensively: this decodes an object written by a
    /// build that knew nothing about this type.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = (try? container.decodeIfPresent(LightingMode.self, forKey: .mode)) ?? nil
        wasActive = mode == .musicSync
        lightbarStyle = (try? container.decodeIfPresent(MusicSyncStyle.self, forKey: .musicSyncStyle)) ?? nil
        playerLEDStyle = (try? container.decodeIfPresent(PlayerLEDAudioStyle.self, forKey: .playerLEDAudioStyle)) ?? nil
        hapticsStyle = (try? container.decodeIfPresent(MusicHapticsStyle.self, forKey: .musicHapticsStyle)) ?? nil
        hapticsIntensity = (try? container.decodeIfPresent(Double.self, forKey: .musicHapticsIntensity)) ?? nil
        sensitivity = (try? container.decodeIfPresent(Double.self, forKey: .audioSensitivity)) ?? nil
        smoothing = (try? container.decodeIfPresent(Double.self, forKey: .audioSmoothing)) ?? nil
        minimumBrightness = (try? container.decodeIfPresent(Double.self, forKey: .audioMinimumBrightness)) ?? nil
    }
}
