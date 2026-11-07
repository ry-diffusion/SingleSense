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
