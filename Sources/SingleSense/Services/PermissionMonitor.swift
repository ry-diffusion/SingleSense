import Foundation
import Combine
import AppKit
import CoreGraphics
import ApplicationServices

/// Watches the system permissions the app depends on and republishes them the
/// moment they change.
///
/// Granting a permission happens in System Settings, outside this process, and
/// neither TCC database emits a reliable callback. Without an active watcher
/// the app only notices on the next `onAppear`, which is why a grant used to
/// require navigating away and back — or relaunching.
///
/// Three signals cover it between them:
///  - the app becoming active again, which is the common case of returning
///    from System Settings;
///  - a distributed notification the accessibility subsystem posts when its
///    trust database changes;
///  - a slow poll, which is the only thing that catches Screen Recording and
///    a grant made without ever leaving the app.
///
/// Screen Recording needs one extra step. `CGPreflightScreenCaptureAccess`
/// answers from a cache the system fills the first time the process asks: once
/// it has said "no" it keeps saying "no" until the app is relaunched, so
/// polling it can never see the grant land. The window list can — see
/// `canReadOtherWindowTitles()`.
public final class PermissionMonitor: ObservableObject {
    public static let shared = PermissionMonitor()

    @Published public private(set) var hasAccessibility: Bool = AXIsProcessTrusted()
    @Published public private(set) var hasScreenRecording: Bool = CGPreflightScreenCaptureAccess()
    @Published public private(set) var hasPromptedScreenRecording: Bool = UserDefaults.standard.bool(forKey: promptedScreenRecordingKey) || CGPreflightScreenCaptureAccess()

    private static let promptedScreenRecordingKey = "hasPromptedScreenRecording"

    /// Fires whenever a permission flips from denied to granted, so features
    /// can start themselves instead of waiting to be asked again.
    public let granted = PassthroughSubject<Permission, Never>()

    public enum Permission {
        case accessibility
        case screenRecording
    }

    /// Slow enough to be free, quick enough that the grant feels instant.
    private static let pollInterval: TimeInterval = 1.0

    private var pollTimer: Timer?
    private var observers: [Any] = []
    private var distributedObservers: [Any] = []
    private var isObserving = false

    /// The window-list probe only runs while a feature is actually waiting on
    /// the permission.
    private var screenRecordingWatchers = 0
    /// Latched once the probe succeeds, because the stale preflight cache would
    /// otherwise pull the published value straight back down to `false`.
    private var probedScreenRecording = false

    private init() {}

    // MARK: - Lifecycle

    public func start() {
        guard !isObserving else { return }
        isObserving = true

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        })

        // Posted when the accessibility trust database changes, which is the
        // instant the user ticks the box in System Settings.
        distributedObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil, queue: .main
        ) { [weak self] _ in
            // The database is written slightly after the notification lands.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.refresh()
            }
        })

        updatePolling()
    }

    public func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        distributedObservers.forEach(DistributedNotificationCenter.default().removeObserver)
        distributedObservers.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        isObserving = false
    }

    // MARK: - Checking

    /// Call while a feature needs Screen Recording, and balance it with
    /// `endWatchingScreenRecording()`. Only while it is being watched does the
    /// monitor pay for the probe that can see a fresh grant.
    public func beginWatchingScreenRecording() {
        screenRecordingWatchers += 1
        refresh()
    }

    public func endWatchingScreenRecording() {
        screenRecordingWatchers = max(0, screenRecordingWatchers - 1)
    }

    /// Re-reads both permissions and publishes any change. Never prompts: this
    /// runs on a timer, so anything that can put a system alert on screen would
    /// put one there every tick.
    public func refresh() {
        if !probedScreenRecording, screenRecordingWatchers > 0, Self.canReadOtherWindowTitles() {
            probedScreenRecording = true
        }
        apply(
            accessibility: AXIsProcessTrusted(),
            screenRecording: CGPreflightScreenCaptureAccess() || probedScreenRecording
        )
    }

    private func apply(accessibility: Bool, screenRecording: Bool) {
        let accessibilityChanged = accessibility != hasAccessibility
        let screenRecordingChanged = screenRecording != hasScreenRecording
        guard accessibilityChanged || screenRecordingChanged else { return }

        // The poll runs in .common mode, so this can land mid-view-update.
        publishOnNextRunLoopTurn { [weak self] in
            guard let self = self else { return }
            if accessibilityChanged {
                self.hasAccessibility = accessibility
                if accessibility { self.granted.send(.accessibility) }
            }
            if screenRecordingChanged {
                self.hasScreenRecording = screenRecording
                if screenRecording { self.granted.send(.screenRecording) }
            }
            self.updatePolling()
        }
    }

    /// Reads Screen Recording state without prompting, by looking for a window
    /// title that belongs to another process.
    ///
    /// The system strips those titles from the window list unless the caller
    /// holds Screen Recording, and unlike the preflight answer the window list
    /// is not cached, so this sees the grant arrive. Asking ScreenCaptureKit
    /// would be the direct question, but on a denial it puts the "would like to
    /// record this computer's screen" alert on screen — once per call.
    ///
    /// Only a positive answer means anything. A screen with nothing but
    /// Single Sense on it looks exactly like a denial, so this can promote the
    /// permission to granted but must never take it away.
    private static func canReadOtherWindowTitles() -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        // These own on-screen surfaces whose names are readable without the
        // permission, so a title from them proves nothing.
        let uninformativeOwners: Set<String> = [
            "Window Server", "Dock", "SystemUIServer", "Control Center", "Spotlight"
        ]

        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let owner = window[kCGWindowOwnerName as String] as? String,
                  !uninformativeOwners.contains(owner),
                  let title = window[kCGWindowName as String] as? String
            else { return false }
            return !title.isEmpty
        }
    }

    /// Quits and reopens the app, which is the only way a process that was
    /// already running when the grant landed can pick it up.
    public func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// Polls only while something is still missing; a fully granted app costs
    /// nothing.
    private func updatePolling() {
        let needsPolling = isObserving && !(hasAccessibility && hasScreenRecording)

        if needsPolling, pollTimer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                self?.refresh()
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        } else if !needsPolling, pollTimer != nil {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    // MARK: - Requesting

    /// Shows the system's own accessibility prompt.
    public func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        updatePolling()
    }

    /// Shows the system's own screen-recording prompt.
    public func requestScreenRecording() {
        UserDefaults.standard.set(true, forKey: Self.promptedScreenRecordingKey)
        hasPromptedScreenRecording = true
        // Returns immediately; the grant arrives through the probe. Only ever
        // call this from an explicit user action — it is what shows the alert.
        _ = CGRequestScreenCaptureAccess()
        updatePolling()
    }

    public func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    public func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
