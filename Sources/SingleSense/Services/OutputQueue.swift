import Foundation

/// A complete description of what the controller hardware should be doing.
struct DSHardwareState {
    var lightbar: RGBColor
    var playerLEDMask: UInt8
    var playerBrightness: PlayerLEDBrightness
    var micLED: MicLEDMode
    var leftMotor: UInt8
    var rightMotor: UInt8
    var leftTrigger: SingleTriggerConfig
    var rightTrigger: SingleTriggerConfig
    var forceSend: Bool
    /// How many times this state has already failed to reach the device.
    var attempts: Int = 0
}

/// Ordering and backpressure for everything the driver sends.
///
/// Two kinds of work travel here and they need opposite disciplines. Discrete
/// events must all reach the device, in order. Hardware state is a *level*: if
/// three updates pile up behind a slow Bluetooth link, sending all three is
/// pointless — only the newest describes reality. So state coalesces into a
/// single slot while events keep their ordering, and at most one drain is ever
/// outstanding, which is what stops a 60 Hz producer growing an unbounded
/// backlog.
struct DSOutputQueue {
    enum Event: Equatable {
        case ledReset
    }

    /// Work handed to a single drain pass.
    struct Batch {
        var events: [Event]
        var state: DSHardwareState?
    }

    private(set) var events: [Event] = []
    private(set) var state: DSHardwareState?
    /// True while a drain pass is scheduled or running.
    private(set) var drainScheduled = false
    /// State updates superseded before they reached the device. Diagnostic
    /// only, but it is the number that says the link is saturated.
    private(set) var coalescedStateUpdates: UInt64 = 0

    /// Adds an event. Returns true when the caller must schedule a drain.
    mutating func enqueue(_ event: Event) -> Bool {
        events.append(event)
        return claimDrain()
    }

    /// Replaces the pending state. Returns true when the caller must schedule
    /// a drain.
    mutating func enqueue(_ newState: DSHardwareState) -> Bool {
        var next = newState
        if let superseded = state {
            coalescedStateUpdates += 1
            // A pending forced send must not be swallowed by the ordinary
            // update that replaces it.
            if superseded.forceSend { next.forceSend = true }
        }
        state = next
        return claimDrain()
    }

    private mutating func claimDrain() -> Bool {
        let needed = !drainScheduled
        drainScheduled = true
        return needed
    }

    /// Takes everything currently pending. Returns nil when the queue has run
    /// dry, which also ends the drain pass.
    mutating func takeWork() -> Batch? {
        guard !events.isEmpty || state != nil else {
            drainScheduled = false
            return nil
        }
        let batch = Batch(events: events, state: state)
        events.removeAll(keepingCapacity: true)
        state = nil
        return batch
    }

    /// Puts a refused state back for one more attempt. A newer state that
    /// arrived meanwhile supersedes it and wins.
    mutating func requeue(_ refused: DSHardwareState) {
        guard state == nil else { return }
        var retry = refused
        retry.forceSend = true
        retry.attempts += 1
        state = retry
    }

    /// Drops the backlog — used when the device goes away, so nothing is
    /// replayed at whatever attaches next.
    mutating func clear() {
        events.removeAll()
        state = nil
        drainScheduled = false
    }
}

/// Suppresses reports the controller already has.
///
/// The rule that matters: a report is only remembered once the device has
/// actually taken it. Recording it before the write is confirmed makes the
/// filter suppress every retry of a report that never arrived, and the change
/// is silently lost until the keepalive — which is what made adaptive triggers
/// work only sometimes.
struct DSSendDeduplicator {
    /// Identical state is re-sent this often as a keepalive.
    static let keepalive: TimeInterval = 2.0

    private var lastPayload: [UInt8] = []
    private var lastSentTime: Date = .distantPast

    func shouldSend(_ report: [UInt8], forced: Bool, now: Date) -> Bool {
        if forced { return true }
        if report != lastPayload { return true }
        return now.timeIntervalSince(lastSentTime) >= Self.keepalive
    }

    /// Call only after the device accepted the report.
    mutating func commit(_ report: [UInt8], at time: Date) {
        lastPayload = report
        lastSentTime = time
    }

    /// Call when the device refused it, so the retry is not suppressed.
    mutating func invalidate() {
        lastPayload = []
        lastSentTime = .distantPast
    }
}
