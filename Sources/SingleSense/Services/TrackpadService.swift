import Foundation
import Combine
import AppKit
import ApplicationServices

/// Drives the macOS cursor from the DualSense touchpad.
///
/// The touchpad is reported as two absolute contact points in the HID input
/// report. macOS is driven with relative motion instead, because the pad is
/// far smaller than the desktop and absolute mapping makes it unusable.
///
/// Posting synthetic mouse events requires the Accessibility permission; the
/// service reports that state rather than failing silently.
public final class TrackpadService: ObservableObject {
    public static let shared = TrackpadService()

    /// Off by default — this takes over the user's cursor.
    @Published public var isEnabled: Bool = false {
        didSet { if !isEnabled { reset() } }
    }
    /// Desktop pixels travelled per unit of pad travel.
    @Published public var sensitivity: Double = 1600
    /// Scroll pixels per unit of pad travel.
    @Published public var scrollSensitivity: Double = 900
    @Published public var naturalScrolling: Bool = true
    @Published public var tapToClick: Bool = true

    @Published public private(set) var hasPermission: Bool = AXIsProcessTrusted()
    /// Mirrors the live contact state for the UI.
    @Published public private(set) var contactCount: Int = 0

    private let eventSource = CGEventSource(stateID: .combinedSessionState)

    /// All gesture rules live here; this class only turns the decisions into
    /// CGEvents. Touched only on the HID I/O thread.
    private var recognizer = TrackpadGestureRecognizer()

    private var syntheticButtonDown = false

    private init() {}

    /// Re-checks the Accessibility permission, prompting when asked to.
    @discardableResult
    public func refreshPermission(prompt: Bool = false) -> Bool {
        let granted: Bool
        if prompt {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            granted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        } else {
            granted = AXIsProcessTrusted()
        }
        DispatchQueue.main.async { self.hasPermission = granted }
        return granted
    }

    public func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func reset() {
        recognizer.reset()
        if syntheticButtonDown {
            postButton(down: false, right: false)
        }
    }

    // MARK: - Input

    /// Consumes one touchpad sample. Called on the HID I/O thread for every
    /// input report, so the cursor tracks at the controller's full rate.
    public func handle(
        primaryActive: Bool, primaryX: Float, primaryY: Float,
        secondaryActive: Bool, secondaryX: Float, secondaryY: Float,
        buttonDown: Bool
    ) {
        guard isEnabled, hasPermission else { return }

        recognizer.sensitivity = sensitivity
        recognizer.scrollSensitivity = scrollSensitivity
        recognizer.naturalScrolling = naturalScrolling
        recognizer.tapToClick = tapToClick

        let actions = recognizer.process(TrackpadSample(
            primaryActive: primaryActive, primaryX: primaryX, primaryY: primaryY,
            secondaryActive: secondaryActive, secondaryX: secondaryX, secondaryY: secondaryY,
            buttonDown: buttonDown, time: CACurrentMediaTime()
        ))

        let fingers = recognizer.contactCount
        if fingers != contactCount {
            DispatchQueue.main.async { self.contactCount = fingers }
        }

        for action in actions { perform(action) }
    }

    private func perform(_ action: TrackpadAction) {
        switch action {
        case .move(let dx, let dy):
            moveCursor(dx: dx, dy: dy, dragging: false)
        case .drag(let dx, let dy):
            moveCursor(dx: dx, dy: dy, dragging: true)
        case .scroll(let dx, let dy):
            postScroll(dx: dx, dy: dy)
        case .button(let down, let right):
            postButton(down: down, right: right)
        }
    }

    private func moveCursor(dx: Double, dy: Double, dragging: Bool) {
        let current = CGEvent(source: nil)?.location ?? .zero
        let target = clampToDisplays(CGPoint(x: current.x + dx, y: current.y + dy))
        let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: dragging ? .leftMouseDragged : .mouseMoved,
            mouseCursorPosition: target,
            mouseButton: .left
        )
        event?.post(tap: .cghidEventTap)
    }

    private func postScroll(dx: Double, dy: Double) {
        let vertical = Int32(dy.rounded())
        let horizontal = Int32(dx.rounded())
        guard vertical != 0 || horizontal != 0 else { return }
        let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        )
        event?.post(tap: .cghidEventTap)
    }

    private func postButton(down: Bool, right: Bool) {
        let position = CGEvent(source: nil)?.location ?? .zero
        let type: CGEventType = right
            ? (down ? .rightMouseDown : .rightMouseUp)
            : (down ? .leftMouseDown : .leftMouseUp)
        let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: type,
            mouseCursorPosition: position,
            mouseButton: right ? .right : .left
        )
        event?.post(tap: .cghidEventTap)
        syntheticButtonDown = down
    }

    /// Keeps the cursor inside the union of the attached displays.
    private func clampToDisplays(_ point: CGPoint) -> CGPoint {
        var bounds = CGRect.null
        for screen in NSScreen.screens {
            // NSScreen is bottom-left origin; CGEvent is top-left. Only the
            // size and relative placement matter for clamping, so union the
            // frames and flip against the primary display's height.
            bounds = bounds.union(screen.frame)
        }
        guard !bounds.isNull, let primary = NSScreen.screens.first else { return point }

        let flippedMinY = primary.frame.maxY - bounds.maxY
        let flippedMaxY = flippedMinY + bounds.height
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX - 1),
            y: min(max(point.y, flippedMinY), flippedMaxY - 1)
        )
    }
}
