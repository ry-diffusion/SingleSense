import Foundation
import Combine

/// Everything the app should still be doing the next time it opens.
///
/// Profiles are saved separately; this is the live working state, which used
/// to be rebuilt from defaults on every launch.
public struct SessionSettings: Codable, Equatable {
    public var lightbar = LightbarConfiguration()
    public var musicSync = MusicSyncConfiguration()
    public var speaker = SpeakerConfiguration()
    public var leftTrigger = SingleTriggerConfig()
    public var rightTrigger = SingleTriggerConfig()
    public var triggersLinked = false
    public var leftRumble: Float = 0
    public var rightRumble: Float = 0
    public var activeProfileId: UUID?

    public var trackpadEnabled = false
    public var trackpadSensitivity: Double = 1600
    public var trackpadScrollSensitivity: Double = 900
    public var trackpadNaturalScrolling = true
    public var trackpadTapToClick = true

    public init() {}

    /// Decoding tolerates a file written by an older build, or a hand-edited
    /// one, by falling back per field rather than discarding the whole thing.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SessionSettings()
        lightbar = try container.decodeIfPresent(LightbarConfiguration.self, forKey: .lightbar) ?? fallback.lightbar
        // Its own key when the file was written after the split, and the old
        // music fields inside `lightbar` when it was written before.
        if let stored = (try? container.decodeIfPresent(MusicSyncConfiguration.self, forKey: .musicSync)) ?? nil {
            musicSync = stored
        } else if let legacy = try? container.decode(MusicSyncConfiguration.Legacy.self, forKey: .lightbar) {
            musicSync = .migrated(from: legacy)
        } else {
            musicSync = fallback.musicSync
        }
        // Music Sync used to be a lighting mode. Now that it drives the bar
        // from the outside, leave the mode on one the bar can actually show
        // once the music stops.
        if lightbar.mode == .musicSync { lightbar.mode = .staticColor }
        speaker = (try? container.decodeIfPresent(SpeakerConfiguration.self, forKey: .speaker)) ?? fallback.speaker
        leftTrigger = try container.decodeIfPresent(SingleTriggerConfig.self, forKey: .leftTrigger) ?? fallback.leftTrigger
        rightTrigger = try container.decodeIfPresent(SingleTriggerConfig.self, forKey: .rightTrigger) ?? fallback.rightTrigger
        triggersLinked = try container.decodeIfPresent(Bool.self, forKey: .triggersLinked) ?? fallback.triggersLinked
        leftRumble = DSScale.clamp01(try container.decodeIfPresent(Float.self, forKey: .leftRumble) ?? 0)
        rightRumble = DSScale.clamp01(try container.decodeIfPresent(Float.self, forKey: .rightRumble) ?? 0)
        activeProfileId = try container.decodeIfPresent(UUID.self, forKey: .activeProfileId)

        trackpadEnabled = try container.decodeIfPresent(Bool.self, forKey: .trackpadEnabled) ?? fallback.trackpadEnabled
        trackpadSensitivity = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .trackpadSensitivity) ?? fallback.trackpadSensitivity,
            400...3200, fallback.trackpadSensitivity
        )
        trackpadScrollSensitivity = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .trackpadScrollSensitivity) ?? fallback.trackpadScrollSensitivity,
            200...2000, fallback.trackpadScrollSensitivity
        )
        trackpadNaturalScrolling = try container.decodeIfPresent(Bool.self, forKey: .trackpadNaturalScrolling) ?? fallback.trackpadNaturalScrolling
        trackpadTapToClick = try container.decodeIfPresent(Bool.self, forKey: .trackpadTapToClick) ?? fallback.trackpadTapToClick
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// Reads and writes `SessionSettings` to Application Support.
///
/// Writes are coalesced: dragging a slider changes state dozens of times a
/// second and none of those intermediate values are worth a disk write.
public final class SettingsStore {
    public static let shared = SettingsStore()

    /// Long enough to swallow a slider drag, short enough that quitting right
    /// after a change still keeps it.
    private static let writeDelay: TimeInterval = 0.4

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.singlesense.settings", qos: .utility)
    private var pending: DispatchWorkItem?
    private let directory: URL

    private var fileURL: URL {
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("session.json")
    }

    /// The directory is injectable so tests never touch the real one.
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SingleSense", isDirectory: true)
    }

    /// Never throws: a missing, truncated or hand-mangled file falls back to
    /// defaults rather than leaving the app with no working state.
    public func load() -> SessionSettings {
        guard let data = try? Data(contentsOf: fileURL) else { return SessionSettings() }
        guard let settings = try? JSONDecoder().decode(SessionSettings.self, from: data) else {
            print("[Single Sense] session.json could not be read; starting from defaults")
            return SessionSettings()
        }
        return settings
    }

    /// Schedules a write, replacing any write still waiting.
    public func save(_ settings: SessionSettings) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.writeNow(settings)
        }
        pending = work
        queue.asyncAfter(deadline: .now() + Self.writeDelay, execute: work)
    }

    /// Writes immediately, for app termination where there is no later turn.
    public func flush(_ settings: SessionSettings) {
        pending?.cancel()
        pending = nil
        queue.sync { writeNow(settings) }
    }

    private func writeNow(_ settings: SessionSettings) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: fileURL, options: .atomic)
        } catch {
            print("[Single Sense] Failed to save session settings: \(error)")
        }
    }
}
