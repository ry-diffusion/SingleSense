import Foundation

/// Playing the Mac's sound through the controller instead of the Mac.
public struct SpeakerConfiguration: Codable, Equatable {
    public var isEnabled = false
    /// `0...1`, the position of the volume slider.
    public var volume: Double = 0.8

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SpeakerConfiguration()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? fallback.isEnabled
        let stored = try container.decodeIfPresent(Double.self, forKey: .volume) ?? fallback.volume
        volume = stored.isFinite ? min(max(stored, 0), 1) : fallback.volume
    }

    /// Linear gain applied to the signal. Squaring the slider position makes
    /// equal steps sound roughly equal, instead of all the change crowding
    /// into the bottom of the travel.
    public var gain: Float {
        guard volume.isFinite else { return 0 }
        let clamped = Float(min(max(volume, 0), 1))
        return clamped * clamped
    }
}

/// The grips as a subwoofer: the voice coils play the bass of whatever the
/// Mac is playing.
public struct SubwooferConfiguration: Codable, Equatable {
    public static let crossoverRange: ClosedRange<Double> = 60...200

    public var isEnabled = false
    /// `0...1`.
    public var level: Double = 0.7
    /// Everything below goes to the grips; with the speaker on, everything
    /// above goes to the speaker.
    public var crossoverHz: Double = 120
    public var boostDeepBass = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SubwooferConfiguration()
        isEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? fallback.isEnabled
        boostDeepBass = (try? container.decodeIfPresent(Bool.self, forKey: .boostDeepBass)) ?? fallback.boostDeepBass
        level = Self.clamped(try? container.decodeIfPresent(Double.self, forKey: .level), 0...1, fallback.level)
        crossoverHz = Self.clamped(
            try? container.decodeIfPresent(Double.self, forKey: .crossoverHz),
            Self.crossoverRange, fallback.crossoverHz
        )
    }

    private static func clamped(_ value: Double??, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        guard let value = value ?? nil, value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// What the coil mixer needs. The level is squared like the speaker
    /// volume, so the slider's travel sounds even.
    public var settings: SubwooferSettings {
        let l = Float(min(max(level, 0), 1))
        return SubwooferSettings(level: l * l, crossoverHz: Float(crossoverHz), boostDeepBass: boostDeepBass)
    }
}
