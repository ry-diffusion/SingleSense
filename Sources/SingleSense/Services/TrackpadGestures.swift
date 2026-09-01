import Foundation

/// One touchpad reading, as the HID input report describes it.
public struct TrackpadSample: Equatable {
    public var primaryActive: Bool
    public var primaryX: Float
    public var primaryY: Float
    public var secondaryActive: Bool
    public var secondaryX: Float
    public var secondaryY: Float
    public var buttonDown: Bool
    /// Seconds on a monotonic clock.
    public var time: TimeInterval

    public init(
        primaryActive: Bool = false, primaryX: Float = 0, primaryY: Float = 0,
        secondaryActive: Bool = false, secondaryX: Float = 0, secondaryY: Float = 0,
        buttonDown: Bool = false, time: TimeInterval = 0
    ) {
        self.primaryActive = primaryActive
        self.primaryX = primaryX
        self.primaryY = primaryY
        self.secondaryActive = secondaryActive
        self.secondaryX = secondaryX
        self.secondaryY = secondaryY
        self.buttonDown = buttonDown
        self.time = time
    }
}

/// What the recognizer decided the user meant, in desktop pixels.
public enum TrackpadAction: Equatable {
    case move(dx: Double, dy: Double)
    /// Movement while a button is held — a drag rather than a hover.
    case drag(dx: Double, dy: Double)
    case scroll(dx: Double, dy: Double)
    case button(down: Bool, right: Bool)
}

/// Turns touchpad samples into pointer actions.
///
/// Kept free of AppKit so the gesture rules can be exercised without moving
/// the real cursor.
public struct TrackpadGestureRecognizer {
    /// A contact shorter than this, that moved less than `tapMovementLimit`,
    /// counts as a tap rather than a nudge of the pointer.
    public static let tapDuration: TimeInterval = 0.25
    public static let tapMovementLimit: Float = 0.04
    /// Motion below this is sensor jitter, not intent.
    public static let jitter: Float = 0.0008
    /// A finger lifting and landing elsewhere arrives as one huge delta; past
    /// this it is treated as a new contact instead of flinging the pointer.
    public static let teleportLimit: Float = 0.25

    public var sensitivity: Double = 1600
    public var scrollSensitivity: Double = 900
    public var naturalScrolling: Bool = true
    public var tapToClick: Bool = true

    private var lastPrimary: (x: Float, y: Float)?
    private var lastCentre: (x: Float, y: Float)?
    private var contactStarted: TimeInterval = 0
    private var contactTravel: Float = 0
    private var peakFingers = 0
    private var buttonWasDown = false

    public init() {}

    public private(set) var contactCount = 0

    public mutating func reset() {
        lastPrimary = nil
        lastCentre = nil
        contactTravel = 0
        peakFingers = 0
        contactCount = 0
    }

    public mutating func process(_ sample: TrackpadSample) -> [TrackpadAction] {
        var actions: [TrackpadAction] = []
        let fingers = (sample.primaryActive ? 1 : 0) + (sample.secondaryActive ? 1 : 0)
        contactCount = fingers

        // The physical click is a plain button. Two fingers resting on the pad
        // turn it into a secondary click, the way a Mac trackpad behaves.
        if sample.buttonDown != buttonWasDown {
            buttonWasDown = sample.buttonDown
            actions.append(.button(down: sample.buttonDown, right: fingers >= 2))
        }

        guard fingers > 0 else {
            actions.append(contentsOf: finishContact(at: sample.time))
            return actions
        }

        if peakFingers == 0 {
            contactStarted = sample.time
            contactTravel = 0
        }
        peakFingers = max(peakFingers, fingers)

        if fingers >= 2 {
            lastPrimary = (sample.primaryX, sample.primaryY)
            let centreX = (sample.primaryX + sample.secondaryX) / 2
            let centreY = (sample.primaryY + sample.secondaryY) / 2
            if let action = scroll(to: (centreX, centreY)) { actions.append(action) }
        } else {
            lastCentre = nil
            if let action = pointer(to: (sample.primaryX, sample.primaryY)) { actions.append(action) }
        }

        return actions
    }

    private mutating func pointer(to point: (x: Float, y: Float)) -> TrackpadAction? {
        defer { lastPrimary = point }
        guard let previous = lastPrimary else { return nil }

        let dx = point.x - previous.x
        let dy = point.y - previous.y
        contactTravel += abs(dx) + abs(dy)

        guard abs(dx) > Self.jitter || abs(dy) > Self.jitter else { return nil }
        guard abs(dx) < Self.teleportLimit, abs(dy) < Self.teleportLimit else { return nil }

        // The pad's Y already grows downward, matching screen coordinates.
        let moveX = Double(dx) * sensitivity
        let moveY = Double(dy) * sensitivity
        return buttonWasDown ? .drag(dx: moveX, dy: moveY) : .move(dx: moveX, dy: moveY)
    }

    private mutating func scroll(to centre: (x: Float, y: Float)) -> TrackpadAction? {
        defer { lastCentre = centre }
        guard let previous = lastCentre else { return nil }

        let dx = centre.x - previous.x
        let dy = centre.y - previous.y
        contactTravel += abs(dx) + abs(dy)

        guard abs(dx) > Self.jitter || abs(dy) > Self.jitter else { return nil }
        guard abs(dx) < Self.teleportLimit, abs(dy) < Self.teleportLimit else { return nil }

        let direction: Double = naturalScrolling ? 1 : -1
        return .scroll(
            dx: Double(-dx) * scrollSensitivity * direction,
            dy: Double(-dy) * scrollSensitivity * direction
        )
    }

    private mutating func finishContact(at time: TimeInterval) -> [TrackpadAction] {
        let fingers = peakFingers
        let travel = contactTravel
        let held = time - contactStarted

        lastPrimary = nil
        lastCentre = nil
        peakFingers = 0
        contactTravel = 0

        guard tapToClick, fingers > 0, !buttonWasDown else { return [] }
        guard held < Self.tapDuration, travel < Self.tapMovementLimit else { return [] }

        // One finger taps, two fingers open the context menu.
        let right = fingers >= 2
        return [.button(down: true, right: right), .button(down: false, right: right)]
    }
}
