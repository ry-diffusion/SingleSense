import Foundation

/// One analysed audio window, stamped with the moment in the audio it
/// describes.
struct AnalysisFrame: Equatable {
    let time: TimeInterval
    let levels: AudioLevels
}

/// Buffers analysed audio frames between the analyser and the lightbar.
///
/// The analyser runs at `sampleRate / hop` (~94 Hz) while the lightbar is
/// driven at 60 Hz. Without a queue the faster producer simply overwrites
/// itself, and every transient landing between two consumer ticks is lost —
/// which is what makes the output drift out of step with what is being heard.
struct AnalysisFrameQueue {
    /// Bounded so a stalled consumer costs latency, never unbounded memory.
    /// 64 frames is roughly 680 ms of backlog.
    static let capacity = 64
    /// Give up and report silence after this long with nothing deliverable,
    /// so a stalled stream cannot leave the lightbar and motors stuck on.
    static let staleAfter: TimeInterval = 0.25

    private var frames: [AnalysisFrame] = []
    private var lastDelivered = AudioLevels.silent
    private var lastDeliveredTime: TimeInterval = 0
    /// Frames dropped because the consumer fell too far behind.
    private(set) var droppedFrames: Int = 0

    var depth: Int { frames.count }

    mutating func append(contentsOf newFrames: [AnalysisFrame]) {
        frames.append(contentsOf: newFrames)
        if frames.count > Self.capacity {
            let excess = frames.count - Self.capacity
            droppedFrames += excess
            frames.removeFirst(excess)
        }
    }

    /// Drains every frame due by `now`, in order.
    ///
    /// Continuous bands take the newest value, but percussion pulses are
    /// peak-held across the drained span so a 60 Hz tick cannot skip them.
    mutating func drain(upTo now: TimeInterval) -> AudioLevels {
        var latest: AudioLevels?
        var beatPeak: Float = 0
        var kickPeak: Float = 0
        var snarePeak: Float = 0

        while let first = frames.first, first.time <= now {
            frames.removeFirst()
            beatPeak = max(beatPeak, first.levels.beat)
            kickPeak = max(kickPeak, first.levels.kick)
            snarePeak = max(snarePeak, first.levels.snare)
            latest = first.levels
        }

        if var result = latest {
            result.beat = beatPeak
            result.kick = kickPeak
            result.snare = snarePeak
            lastDelivered = result
            lastDeliveredTime = now
            return result
        }

        // Hold continuous levels through jitter, but never latch a transient
        // at full strength while the producer is briefly late.
        if now - lastDeliveredTime > 0.05 {
            lastDelivered.beat = 0
            lastDelivered.kick = 0
            lastDelivered.snare = 0
        }
        if now - lastDeliveredTime > Self.staleAfter {
            lastDelivered = .silent
        }
        return lastDelivered
    }

    mutating func reset() {
        frames.removeAll(keepingCapacity: true)
        lastDelivered = .silent
        lastDeliveredTime = 0
        droppedFrames = 0
    }
}
