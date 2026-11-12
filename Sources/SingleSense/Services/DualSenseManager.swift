import Foundation
import Combine
import GameController
import CoreHaptics

public final class DualSenseManager: ObservableObject {
    public static let shared = DualSenseManager()
    
    @Published public var controllerState = ControllerState()
    @Published public var lightbarConfig = LightbarConfiguration()
    @Published public var musicSyncConfig = MusicSyncConfiguration()
    @Published public var speakerConfig = SpeakerConfiguration()
    @Published public var subwooferConfig = SubwooferConfiguration()
    @Published public var leftTriggerConfig = SingleTriggerConfig()
    @Published public var rightTriggerConfig = SingleTriggerConfig()
    @Published public var triggersLinked: Bool = false
    @Published public var leftRumbleIntensity: Float = 0.0
    @Published public var rightRumbleIntensity: Float = 0.0
    @Published public var isTriggerDynoTestActive: Bool = false
    
    /// Trigger effects the dyno test wants right now. The HID path owns the
    /// device, so the buzz has to travel in the output report rather than
    /// through GCDualSenseAdaptiveTrigger.
    /// True while the raw HID path owns the device.
    ///
    /// Everything prefers HID: it is the only path with the real trigger
    /// encoder, the factory IMU calibration and the player LEDs. The
    /// GameController framework stays as a degraded fallback for when
    /// IOHIDDeviceOpen fails — another app holding the device, or a permission
    /// problem — and must never run alongside HID, because two writers fighting
    /// over the same report make the lightbar flicker and the triggers stutter.
    private var usesHIDPath: Bool { HIDDriver.shared.isDeviceOpen }

    /// The colour currently being driven, readable without waiting for the
    /// published copy to land. Hardware must never read a stale value.
    private var currentColor = RGBColor(red: 0.0, green: 0.4, blue: 1.0)

    /// Set once the speaker has been switched on this session. From then on
    /// every report carries an explicit route, so switching it off actually
    /// hands the sound back to the jack instead of leaving the speaker live.
    private var speakerRouteTouched = false

    /// Edge detector for the beat thump Music Sync plays on the coils.
    private var coilBeatHigh = false

    private var dynoLeftTrigger = SingleTriggerConfig(mode: .off)
    private var dynoRightTrigger = SingleTriggerConfig(mode: .off)

    private var activeGCController: GCController?
    private var activeDualSenseGamepad: GCDualSenseGamepad?
    private var hapticEngine: CHHapticEngine?
    
    private var cancellables = Set<AnyCancellable>()
    private let sendQueue = DispatchQueue(label: "com.singlesense.manager.send", qos: .userInteractive)
    
    /// Suppresses saving while the stored state is being applied, so restoring
    /// does not immediately write back what was just read.
    private var isRestoring = false

    private init() {
        restoreSession()
        setupGameControllerMonitoring()
        setupHIDDriver()
        setupVoiceCoilHandover()
        setupRainbowEngine()
        setupPersistence()
    }

    // MARK: - Persistence

    private func restoreSession() {
        isRestoring = true
        defer { isRestoring = false }

        let saved = SettingsStore.shared.load()
        lightbarConfig = saved.lightbar
        musicSyncConfig = saved.musicSync
        speakerConfig = saved.speaker
        subwooferConfig = saved.subwoofer
        leftTriggerConfig = saved.leftTrigger.sanitized()
        rightTriggerConfig = saved.rightTrigger.sanitized()
        triggersLinked = saved.triggersLinked
        leftRumbleIntensity = DSScale.clamp01(saved.leftRumble)
        rightRumbleIntensity = DSScale.clamp01(saved.rightRumble)
        currentColor = RainbowEngine.shared.calculateColor(
            for: lightbarConfig,
            music: musicSyncConfig,
            elapsed: 0,
            controllerState: controllerState
        )

        let trackpad = TrackpadService.shared
        trackpad.sensitivity = saved.trackpadSensitivity
        trackpad.scrollSensitivity = saved.trackpadScrollSensitivity
        trackpad.naturalScrolling = saved.trackpadNaturalScrolling
        trackpad.tapToClick = saved.trackpadTapToClick
        // Only re-arm the trackpad if it can actually work; otherwise it would
        // look enabled while silently doing nothing.
        trackpad.isEnabled = saved.trackpadEnabled && PermissionMonitor.shared.hasAccessibility

        if let id = saved.activeProfileId {
            ProfileStorage.shared.activeProfileId = id
        }
    }

    /// Persists whenever the working state settles.
    /// The report has to change when the coils open or close: the rumble
    /// emulation holds the actuators until it is told to let go.
    private func setupVoiceCoilHandover() {
        VoiceCoilEngine.shared.$status
            .map { $0 == .running }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateHardwareLightbar(color: self.currentColor, force: true)
            }
            .store(in: &cancellables)
    }

    private func setupPersistence() {
        let manager = Publishers.MergeMany(
            $lightbarConfig.map { _ in () }.eraseToAnyPublisher(),
            $musicSyncConfig.map { _ in () }.eraseToAnyPublisher(),
            $speakerConfig.map { _ in () }.eraseToAnyPublisher(),
            $subwooferConfig.map { _ in () }.eraseToAnyPublisher(),
            $leftTriggerConfig.map { _ in () }.eraseToAnyPublisher(),
            $rightTriggerConfig.map { _ in () }.eraseToAnyPublisher(),
            $triggersLinked.map { _ in () }.eraseToAnyPublisher(),
            $leftRumbleIntensity.map { _ in () }.eraseToAnyPublisher(),
            $rightRumbleIntensity.map { _ in () }.eraseToAnyPublisher()
        )

        let trackpad = TrackpadService.shared
        let trackpadChanges = Publishers.MergeMany(
            trackpad.$isEnabled.map { _ in () }.eraseToAnyPublisher(),
            trackpad.$sensitivity.map { _ in () }.eraseToAnyPublisher(),
            trackpad.$scrollSensitivity.map { _ in () }.eraseToAnyPublisher(),
            trackpad.$naturalScrolling.map { _ in () }.eraseToAnyPublisher(),
            trackpad.$tapToClick.map { _ in () }.eraseToAnyPublisher()
        )

        Publishers.Merge3(
            manager,
            trackpadChanges,
            ProfileStorage.shared.$activeProfileId.map { _ in () }.eraseToAnyPublisher()
        )
        .dropFirst()
        .sink { [weak self] in self?.scheduleSave() }
        .store(in: &cancellables)
    }

    private func scheduleSave() {
        guard !isRestoring else { return }
        SettingsStore.shared.save(currentSessionSettings())
    }

    private func currentSessionSettings() -> SessionSettings {
        var settings = SessionSettings()
        settings.lightbar = lightbarConfig
        settings.musicSync = musicSyncConfig
        settings.speaker = speakerConfig
        settings.subwoofer = subwooferConfig
        settings.leftTrigger = leftTriggerConfig
        settings.rightTrigger = rightTriggerConfig
        settings.triggersLinked = triggersLinked
        settings.leftRumble = leftRumbleIntensity
        settings.rightRumble = rightRumbleIntensity
        settings.activeProfileId = ProfileStorage.shared.activeProfileId

        let trackpad = TrackpadService.shared
        settings.trackpadEnabled = trackpad.isEnabled
        settings.trackpadSensitivity = trackpad.sensitivity
        settings.trackpadScrollSensitivity = trackpad.scrollSensitivity
        settings.trackpadNaturalScrolling = trackpad.naturalScrolling
        settings.trackpadTapToClick = trackpad.tapToClick
        return settings
    }

    /// Writes without waiting for the debounce, for app termination.
    public func flushSettings() {
        SettingsStore.shared.flush(currentSessionSettings())
    }
    
    public func start() {
        HIDDriver.shared.start()
        RainbowEngine.shared.start()
        GCController.startWirelessControllerDiscovery()
        checkInitialControllers()
        // Restored state only reached memory; this puts it on the hardware and
        // starts the audio tap if Music Sync was left switched on.
        applyMusicSyncConfiguration(force: true)
        applySpeakerConfiguration(force: true)
        applyTriggerConfiguration(force: true)
    }
    
    public func stop() {
        flushSettings()
        HIDDriver.shared.stop()
        RainbowEngine.shared.stop()
        AudioReactiveEngine.shared.setActive(false)
        ControllerSpeakerEngine.shared.configure(speaker: false, subwoofer: false)
        VoiceCoilEngine.shared.stop()
        GCController.stopWirelessControllerDiscovery()
    }
    
    // MARK: - GameController Framework Setup
    private func setupGameControllerMonitoring() {
        GCController.shouldMonitorBackgroundEvents = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleControllerConnected(notification:)),
            name: .GCControllerDidConnect,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleControllerDisconnected(notification:)),
            name: .GCControllerDidDisconnect,
            object: nil
        )
    }
    
    private func checkInitialControllers() {
        if let controller = GCController.controllers().first {
            attachController(controller)
        }
    }
    
    @objc private func handleControllerConnected(notification: Notification) {
        if let controller = notification.object as? GCController {
            attachController(controller)
        }
    }
    
    @objc private func handleControllerDisconnected(notification: Notification) {
        if let controller = notification.object as? GCController, controller == activeGCController {
            detachController()
        }
    }
    
    private func attachController(_ controller: GCController) {
        self.activeGCController = controller
        
        let vendor = controller.vendorName ?? "DualSense"
        controllerState.isConnected = true
        controllerState.controllerName = vendor
        
        if vendor.lowercased().contains("edge") {
            controllerState.model = .dualsenseEdge
            controllerState.isEdge = true
        } else {
            controllerState.model = .dualsense
            controllerState.isEdge = false
        }
        
        // Update connection type if not already set by HID
        if controllerState.connectionType == .unknown {
            controllerState.connectionType = .bluetooth // Default or fallback
        }
        
        // Check for GCDualSenseGamepad
        if let dsGamepad = controller.extendedGamepad as? GCDualSenseGamepad {
            self.activeDualSenseGamepad = dsGamepad
        }
        
        bindInputHandlers(controller: controller)
        setupCoreHaptics(controller: controller)
        
        // Push the initial configuration, then again as the link settles. A
        // DualSense still completing its handshake quietly ignores the first
        // report, so these retries have to bypass the dedup filter — otherwise
        // they are byte-identical and get dropped before ever being sent.
        applyTriggerConfiguration(force: true)
        applyLightbarConfiguration(force: true)

        for delay in [0.25, 0.6, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.applyLightbarConfiguration(force: true)
                self?.applyTriggerConfiguration(force: true)
            }
        }
        
        print("[Single Sense] Controller attached: \(vendor)")
    }
    
    private func detachController() {
        activeGCController = nil
        activeDualSenseGamepad = nil
        hapticEngine = nil
        controllerState.isConnected = false
        controllerState.resetInputs()
        print("[Single Sense] Controller detached")
    }
    
    // MARK: - Input Handlers Binding
    private func bindInputHandlers(controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        
        // Action buttons
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            DispatchQueue.main.async { self?.controllerState.buttonCross = pressed }
        }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            DispatchQueue.main.async { self?.controllerState.buttonCircle = pressed }
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            DispatchQueue.main.async { self?.controllerState.buttonSquare = pressed }
        }
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            DispatchQueue.main.async { self?.controllerState.buttonTriangle = pressed }
        }
        
        // D-Pad
        gamepad.dpad.valueChangedHandler = { [weak self] _, x, y in
            DispatchQueue.main.async {
                self?.controllerState.dpadUp = y > 0.4
                self?.controllerState.dpadDown = y < -0.4
                self?.controllerState.dpadLeft = x < -0.4
                self?.controllerState.dpadRight = x > 0.4
            }
        }
        
        // Bumpers
        gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            DispatchQueue.main.async { self?.controllerState.buttonL1 = pressed }
        }
        gamepad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            DispatchQueue.main.async { self?.controllerState.buttonR1 = pressed }
        }
        
        // Triggers with Real-time Dyno Support
        gamepad.leftTrigger.valueChangedHandler = { [weak self] _, value, pressed in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.controllerState.triggerL2 = value
                self.controllerState.buttonL2 = pressed
                if self.isTriggerDynoTestActive || self.lightbarConfig.mode == .triggerReactive {
                    self.handleTriggerDynamicUpdate()
                }
            }
        }
        gamepad.rightTrigger.valueChangedHandler = { [weak self] _, value, pressed in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.controllerState.triggerR2 = value
                self.controllerState.buttonR2 = pressed
                if self.isTriggerDynoTestActive || self.lightbarConfig.mode == .triggerReactive {
                    self.handleTriggerDynamicUpdate()
                }
            }
        }
        
        // Thumbsticks
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            DispatchQueue.main.async {
                self?.controllerState.leftStickX = x
                self?.controllerState.leftStickY = y
            }
        }
        gamepad.leftThumbstickButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            DispatchQueue.main.async { self?.controllerState.buttonL3 = pressed }
        }
        
        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            DispatchQueue.main.async {
                self?.controllerState.rightStickX = x
                self?.controllerState.rightStickY = y
            }
        }
        gamepad.rightThumbstickButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            DispatchQueue.main.async { self?.controllerState.buttonR3 = pressed }
        }
        
        // Menu / Options / Share / PS buttons
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            DispatchQueue.main.async { self?.controllerState.buttonOptions = pressed }
        }
        gamepad.buttonOptions?.pressedChangedHandler = { [weak self] _, _, pressed in
            DispatchQueue.main.async { self?.controllerState.buttonShare = pressed }
        }
        gamepad.buttonHome?.pressedChangedHandler = { [weak self] _, _, pressed in
            DispatchQueue.main.async { self?.controllerState.buttonPS = pressed }
        }
        
        // Touchpad
        if let dsGamepad = gamepad as? GCDualSenseGamepad {
            dsGamepad.touchpadButton.pressedChangedHandler = { [weak self] _, _, pressed in
                DispatchQueue.main.async {
                    self?.controllerState.buttonTouchpad = pressed
                }
            }
            dsGamepad.touchpadPrimary.valueChangedHandler = { [weak self] _, x, y in
                DispatchQueue.main.async {
                    // The HID input report carries a real contact flag and both
                    // touch points; this axis-only approximation cannot tell a
                    // finger resting at dead centre from no finger at all, so it
                    // is a fallback rather than the primary source.
                    guard let self = self, !self.usesHIDPath else { return }
                    self.controllerState.touch1Active = (x != 0 || y != 0)
                    self.controllerState.touch1X = (x + 1.0) / 2.0
                    self.controllerState.touch1Y = (1.0 - y) / 2.0
                }
            }
        }
        
        // Motion sensors (IMU).
        //
        // The HID input report carries the raw gyro and accelerometer plus the
        // controller's own factory calibration, so it is the source whenever it
        // is available. GCMotion is only a fallback: its gravity and
        // userAcceleration need sensor fusion the DualSense does not expose on
        // macOS, and rotationRate is meaningless unless hasRotationRate is set
        // — which is how the gyro ended up mirroring the accelerometer.
        if let motion = controller.motion, !usesHIDPath {
            motion.sensorsActive = true
            motion.valueChangedHandler = { [weak self] (motion: GCMotion) in
                DispatchQueue.main.async {
                    guard let self = self, !self.usesHIDPath else { return }
                    if motion.hasRotationRate {
                        // GCMotion reports radians per second.
                        let toDegrees = Float(180.0 / Double.pi)
                        self.controllerState.gyroPitch = Float(motion.rotationRate.x) * toDegrees
                        self.controllerState.gyroYaw = Float(motion.rotationRate.z) * toDegrees
                        self.controllerState.gyroRoll = Float(motion.rotationRate.y) * toDegrees
                    }
                    self.controllerState.accelX = Float(motion.acceleration.x)
                    self.controllerState.accelY = Float(motion.acceleration.y)
                    self.controllerState.accelZ = Float(motion.acceleration.z)
                }
            }
        }
        
        // Battery: seed from GameController, then let the HID input report keep
        // it current. GCDeviceBattery is only sampled here, so on its own the
        // reading would never change after connect.
        if let battery = controller.battery, !usesHIDPath {
            controllerState.batteryLevel = battery.batteryLevel
            controllerState.isBatteryCharging = (battery.batteryState == .charging || battery.batteryState == .full)
        }
    }
    
    // MARK: - Core Haptics Setup
    private func setupCoreHaptics(controller: GCController) {
        if let haptics = controller.haptics {
            self.hapticEngine = haptics.createEngine(withLocality: .default)
            try? self.hapticEngine?.start()
        }
    }
    
    // MARK: - HID Driver Integration
    private func setupHIDDriver() {
        HIDDriver.shared.onDeviceConnected = { [weak self] isEdge, isBT in
            guard let self = self else { return }
            self.controllerState.isConnected = true
            self.controllerState.connectionType = isBT ? .bluetooth : .usb
            if isEdge {
                self.controllerState.model = .dualsenseEdge
                self.controllerState.isEdge = true
            }
            
            // Push hardware configuration to newly opened HID device
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.applyLightbarConfiguration(force: true)
                self.applyTriggerConfiguration(force: true)
            }
        }
        
        HIDDriver.shared.onInputSnapshot = { [weak self] snapshot in
            self?.applyInputSnapshot(snapshot)
        }

        HIDDriver.shared.onTouchpadSample = { snapshot in
            TrackpadService.shared.handle(
                primaryActive: snapshot.touch1Active,
                primaryX: snapshot.touch1X,
                primaryY: snapshot.touch1Y,
                secondaryActive: snapshot.touch2Active,
                secondaryX: snapshot.touch2X,
                secondaryY: snapshot.touch2Y,
                buttonDown: snapshot.touchpadButton
            )
        }

        HIDDriver.shared.onLinkHealthChanged = { [weak self] health in
            // Surfacing this as the real transport going "Unknown" was a lie:
            // the controller is still connected over the same link, it is just
            // refusing writes.
            self?.controllerState.linkHealth = health
        }

        HIDDriver.shared.onDeviceDisconnected = { [weak self] in
            guard let self = self else { return }
            if self.activeGCController == nil {
                self.controllerState.isConnected = false
                self.controllerState.resetInputs()
            }
        }
    }
    
    /// Applies the fields only the raw HID input report exposes.
    private func applyInputSnapshot(_ snapshot: DSInputSnapshot) {
        controllerState.batteryLevel = snapshot.batteryLevel
        controllerState.isBatteryCharging = snapshot.isCharging
        controllerState.gyroPitch = snapshot.gyroPitch
        controllerState.gyroYaw = snapshot.gyroYaw
        controllerState.gyroRoll = snapshot.gyroRoll
        controllerState.accelX = snapshot.accelX
        controllerState.accelY = snapshot.accelY
        controllerState.accelZ = snapshot.accelZ

        if controllerState.headphonesConnected != snapshot.headphonesConnected {
            controllerState.headphonesConnected = snapshot.headphonesConnected
            // Plugging in moves the sound from the speaker to the jack, and
            // back to stereo.
            if speakerConfig.isEnabled { applySpeakerConfiguration(force: true) }
        }

        controllerState.buttonMute = snapshot.micMuteButton
        controllerState.buttonTouchpad = snapshot.touchpadButton

        controllerState.touch1Active = snapshot.touch1Active
        controllerState.touch1X = snapshot.touch1X
        controllerState.touch1Y = snapshot.touch1Y
        controllerState.touch2Active = snapshot.touch2Active
        controllerState.touch2X = snapshot.touch2X
        controllerState.touch2Y = snapshot.touch2Y

        if controllerState.isEdge {
            controllerState.paddleL4 = snapshot.edgeLeftPaddle
            controllerState.paddleR4 = snapshot.edgeRightPaddle
            controllerState.buttonFnL = snapshot.edgeFN1
            controllerState.buttonFnR = snapshot.edgeFN2
        }

        // Keep the battery gauge lighting mode in step with the new reading.
        if lightbarConfig.mode == .batteryReactive {
            applyLightbarConfiguration()
        }
    }

    // MARK: - Rainbow Engine Integration
    private func setupRainbowEngine() {
        RainbowEngine.shared.onColorTick = { [weak self] color in
            guard let self = self else { return }
            if !self.isTriggerDynoTestActive {
                self.currentColor = color
                publishOnNextRunLoopTurn { [weak self] in
                    self?.controllerState.currentLightbarColor = color
                }
                self.updateHardwareLightbar(color: color)
            }
        }
    }
    
    // MARK: - Trigger Dyno Test Implementation
    public func toggleTriggerDynoTest() {
        isTriggerDynoTestActive.toggle()
        if isTriggerDynoTestActive {
            handleTriggerDynamicUpdate()
        } else {
            // Restore normal settings
            dynoLeftTrigger = SingleTriggerConfig(mode: .off)
            dynoRightTrigger = SingleTriggerConfig(mode: .off)
            applyLightbarConfiguration()
            applyTriggerConfiguration()
            setRumble(left: 0, right: 0)
        }
    }
    
    public func handleTriggerDynamicUpdate() {
        let l2 = controllerState.triggerL2
        let r2 = controllerState.triggerR2
        let maxTrigger = max(l2, r2)
        
        // 1. Color: Smooth Green (0.333) -> Yellow (0.166) -> Orange -> Red (0.0)
        let hue = 0.333 * Double(1.0 - maxTrigger)
        let dynamicColor = RGBColor.fromHSV(hue: hue, saturation: 1.0, value: 1.0)
        currentColor = dynamicColor
        publishOnNextRunLoopTurn { [weak self] in
            self?.controllerState.currentLightbarColor = dynamicColor
        }
        
        // 2. Vibration Intensity & Speed (Left motor heavy weight + Right motor high frequency)
        let leftMotor: Float
        let rightMotor: Float
        if maxTrigger > 0.03 {
            leftMotor = maxTrigger * maxTrigger
            rightMotor = maxTrigger
        } else {
            leftMotor = 0.0
            rightMotor = 0.0
        }
        
        // 3. Adaptive trigger buzz: harder pull, faster buzz (10 Hz to 200 Hz).
        //    These reach the controller inside the output report below.
        let frequency = max(10.0, maxTrigger * 200.0)
        dynoLeftTrigger = Self.dynoTriggerEffect(pressure: l2, frequency: frequency)
        dynoRightTrigger = Self.dynoTriggerEffect(pressure: r2, frequency: frequency)

        // 4. Send hardware report with the dynamic motors and trigger effects.
        updateHardwareLightbar(color: dynamicColor, leftMotorOverride: leftMotor, rightMotorOverride: rightMotor)

        // 5. GameController fallback, only when the HID path is unavailable.
        if let dsGamepad = activeDualSenseGamepad, !usesHIDPath {
            if maxTrigger > 0.03 {
                let freq = max(10.0, maxTrigger * 200.0)
                if l2 > 0.03 {
                    dsGamepad.leftTrigger.setModeVibrationWithStartPosition(0.0, amplitude: l2, frequency: freq)
                } else {
                    dsGamepad.leftTrigger.setModeOff()
                }
                if r2 > 0.03 {
                    dsGamepad.rightTrigger.setModeVibrationWithStartPosition(0.0, amplitude: r2, frequency: freq)
                } else {
                    dsGamepad.rightTrigger.setModeOff()
                }
            } else {
                dsGamepad.leftTrigger.setModeOff()
                dsGamepad.rightTrigger.setModeOff()
            }
        }
    }

    /// A vibration effect whose amplitude tracks how hard the trigger is held.
    private static func dynoTriggerEffect(pressure: Float, frequency: Float) -> SingleTriggerConfig {
        guard pressure > 0.03 else { return SingleTriggerConfig(mode: .off) }
        var config = SingleTriggerConfig(mode: .vibration)
        config.startPosition = 0
        config.amplitude = pressure
        config.frequency = frequency
        return config
    }
    
    // MARK: - Hardware Control Execution
    public func updateHardwareLightbar(
        color: RGBColor,
        leftMotorOverride: Float? = nil,
        rightMotorOverride: Float? = nil,
        force: Bool = false
    ) {
        // Precedence: an explicit override (the dyno test) beats music
        // haptics, which in turn beat the manually set rumble level.
        let music = (leftMotorOverride == nil && rightMotorOverride == nil)
            ? currentMusicRumble()
            : nil
        let left = leftMotorOverride ?? music?.left ?? leftRumbleIntensity
        let right = rightMotorOverride ?? music?.right ?? rightRumbleIntensity
        
        publishOnNextRunLoopTurn { [weak self] in
            self?.controllerState.leftRumbleIntensity = left
            self?.controllerState.rightRumbleIntensity = right
        }
        
        // The raw HID report is authoritative when it is available. Driving
        // GCDeviceLight at the same time makes the two writers overwrite each
        // other and the lightbar flickers between the two colours.
        if usesHIDPath {
            HIDDriver.shared.sendHardwareState(
                lightbar: color,
                playerLEDMask: currentPlayerLEDMask(),
                playerBrightness: lightbarConfig.playerLEDBrightness,
                micLED: lightbarConfig.micLEDMode,
                leftMotor: DSScale.byte(left),
                rightMotor: DSScale.byte(right),
                leftTrigger: isTriggerDynoTestActive ? dynoLeftTrigger : leftTriggerConfig,
                rightTrigger: isTriggerDynoTestActive ? dynoRightTrigger : rightTriggerConfig,
                audioRoute: currentAudioRoute(),
                audioHaptics: VoiceCoilEngine.shared.status == .running,
                forceSend: force
            )
            publishOnNextRunLoopTurn { [weak self] in
                self?.controllerState.packetsSent += 1
            }
        } else if let light = activeGCController?.light {
            light.color = GCColor(red: Float(color.red), green: Float(color.green), blue: Float(color.blue))
            publishOnNextRunLoopTurn { [weak self] in
                self?.controllerState.packetsSent += 1
            }
        }
    }
    
    /// The rumble pair the music is currently asking for, or nil when the
    /// music is not driving the motors.
    private func currentMusicRumble() -> (left: Float, right: Float)? {
        guard musicSyncConfig.isDrivingRumble else { return nil }
        // A subwoofer already has the grips; layering the music's rumble on
        // top would only muddy the bass.
        if subwooferConfig.isEnabled && VoiceCoilEngine.shared.status.canPlay { return nil }
        // On the coils the music is felt directly, so the motors stay out of
        // it — except the beat mode, which the coils play as one thump each.
        if let coilStyle = musicSyncConfig.coilMusicStyle(coilsAvailable: VoiceCoilEngine.shared.status.canPlay) {
            if coilStyle == .beats {
                let beat = AudioReactiveEngine.shared.levels.beat > 0.5
                if beat && !coilBeatHigh {
                    VoiceCoilEngine.shared.punch(strength: Float(musicSyncConfig.hapticsIntensity))
                }
                coilBeatHigh = beat
            }
            return nil
        }
        let levels = AudioReactiveEngine.shared.levels
        return musicSyncConfig.rumble(
            bass: levels.bass,
            mid: levels.mid,
            treble: levels.treble,
            beat: levels.beat
        )
    }

    /// The indicator row's bitmask for this instant, which under Music Sync
    /// tracks the audio rather than a fixed player pattern.
    private func currentPlayerLEDMask() -> UInt8 {
        let levels = musicSyncConfig.isDrivingPlayerLEDs
            ? AudioReactiveEngine.shared.levels
            : .silent
        return lightbarConfig.playerLEDMask(
            music: musicSyncConfig,
            level: levels.overall,
            beat: levels.beat,
            kick: levels.kick,
            snare: levels.snare
        )
    }

    /// Pushes the Music Sync settings to the analysis engine and re-resolves
    /// the hardware, which the music may now be driving.
    public func applyMusicSyncConfiguration(force: Bool = false) {
        // The audio tap is only worth its CPU while something is listening.
        let audio = AudioReactiveEngine.shared
        audio.sensitivity = Float(musicSyncConfig.sensitivity)
        audio.smoothing = Float(musicSyncConfig.smoothing)
        audio.setActive(musicSyncConfig.needsAudioCapture)

        let coils = VoiceCoilEngine.shared
        coils.setMusic(
            style: subwooferConfig.isEnabled ? nil : musicSyncConfig.coilMusicStyle(coilsAvailable: true),
            gain: Float(musicSyncConfig.hapticsIntensity)
        )

        applyLightbarConfiguration(force: force)
    }

    /// Starts or stops the controller's speaker and subwoofer, and re-sends
    /// the routing that goes with them.
    public func applySpeakerConfiguration(force: Bool = false) {
        let speaker = ControllerSpeakerEngine.shared
        let subwoofer = subwooferConfig.isEnabled
        if speakerConfig.isEnabled { speakerRouteTouched = true }
        speaker.setGain(speakerConfig.gain)
        speaker.setStereo(controllerState.headphonesConnected)
        // Speaker and grips together make a 2.1 pair: the speaker gives the
        // bass up to the grips instead of straining at it.
        speaker.setCrossover(subwoofer ? Float(subwooferConfig.crossoverHz) : nil)
        VoiceCoilEngine.shared.setSubwoofer(subwoofer ? subwooferConfig.settings : nil)
        speaker.configure(speaker: speakerConfig.isEnabled, subwoofer: subwoofer)
        // Music Sync gives the grips up to the subwoofer; this re-resolves
        // that and re-sends the report.
        applyMusicSyncConfiguration(force: force)
    }

    /// The audio block for the next report, or nil to leave the controller's
    /// own routing alone — which is the case until the speaker is first used,
    /// and always over Bluetooth, where there is no audio stream to route.
    private func currentAudioRoute() -> DSAudioRoute? {
        guard speakerRouteTouched, controllerState.connectionType == .usb else { return nil }
        guard speakerConfig.isEnabled, !controllerState.headphonesConnected else { return .headphones }
        return .speaker
    }

    public func applyLightbarConfiguration(force: Bool = false) {
        let color = RainbowEngine.shared.calculateColor(
            for: lightbarConfig,
            music: musicSyncConfig,
            elapsed: 0,
            controllerState: controllerState
        )
        currentColor = color
        publishOnNextRunLoopTurn { [weak self] in
            self?.controllerState.currentLightbarColor = color
        }
        updateHardwareLightbar(color: color, force: force)
    }
    
    public func applyTriggerConfiguration(force: Bool = false) {
        if triggersLinked {
            rightTriggerConfig = leftTriggerConfig
        }
        leftTriggerConfig = leftTriggerConfig.sanitized()
        rightTriggerConfig = rightTriggerConfig.sanitized()
        
        // GameController only gets to program the triggers when the HID path is
        // unavailable; otherwise the two encoders disagree (setModeSlopeFeedback
        // and the 10-zone curve have no equivalent in the simple effect modes).
        if let dsGamepad = activeDualSenseGamepad, !usesHIDPath {
            applyAdaptiveTrigger(trigger: dsGamepad.leftTrigger, rawConfig: leftTriggerConfig)
            applyAdaptiveTrigger(trigger: dsGamepad.rightTrigger, rawConfig: rightTriggerConfig)
        }

        updateHardwareLightbar(color: currentColor, force: force)
    }
    
    private func applyAdaptiveTrigger(trigger: GCDualSenseAdaptiveTrigger, rawConfig: SingleTriggerConfig) {
        let config = rawConfig.sanitized()
        switch config.mode {
        case .off:
            trigger.setModeOff()
            
        case .feedback:
            trigger.setModeFeedbackWithStartPosition(
                config.startPosition,
                resistiveStrength: config.strength
            )
            
        case .weapon:
            trigger.setModeWeaponWithStartPosition(
                config.startPosition,
                endPosition: config.endPosition,
                resistiveStrength: config.strength
            )
            
        case .vibration:
            trigger.setModeVibrationWithStartPosition(
                config.startPosition,
                amplitude: config.amplitude,
                frequency: config.frequency
            )
            
        case .slopeFeedback:
            trigger.setModeSlopeFeedback(
                startPosition: config.startPosition,
                endPosition: config.endPosition,
                startStrength: config.startStrength,
                endStrength: config.endStrength
            )
            
        case .machineGun:
            trigger.setModeVibrationWithStartPosition(
                config.startPosition,
                amplitude: config.strength,
                frequency: SingleTriggerConfig.machineGunFrequency
            )
            
        case .customCurve:
            let strengths = GCDualSenseAdaptiveTrigger.PositionalResistiveStrengths(values: (
                config.custom10Zones.indices.contains(0) ? config.custom10Zones[0] : 0,
                config.custom10Zones.indices.contains(1) ? config.custom10Zones[1] : 0,
                config.custom10Zones.indices.contains(2) ? config.custom10Zones[2] : 0,
                config.custom10Zones.indices.contains(3) ? config.custom10Zones[3] : 0,
                config.custom10Zones.indices.contains(4) ? config.custom10Zones[4] : 0,
                config.custom10Zones.indices.contains(5) ? config.custom10Zones[5] : 0,
                config.custom10Zones.indices.contains(6) ? config.custom10Zones[6] : 0,
                config.custom10Zones.indices.contains(7) ? config.custom10Zones[7] : 0,
                config.custom10Zones.indices.contains(8) ? config.custom10Zones[8] : 0,
                config.custom10Zones.indices.contains(9) ? config.custom10Zones[9] : 0
            ))
            trigger.setModeFeedback(resistiveStrengths: strengths)
        }
    }
    
    public func setRumble(left: Float, right: Float) {
        self.leftRumbleIntensity = max(0.0, min(1.0, left))
        self.rightRumbleIntensity = max(0.0, min(1.0, right))
        controllerState.leftRumbleIntensity = self.leftRumbleIntensity
        controllerState.rightRumbleIntensity = self.rightRumbleIntensity
        
        updateHardwareLightbar(color: currentColor)
    }
    
    /// Plays a preset on the voice coils, falling back to CoreHaptics (and
    /// from there to a motor pulse) when the controller is not on USB.
    public func playHaptic(_ preset: HapticPreset, pan: Float = 0) {
        if VoiceCoilEngine.shared.play(preset, pan: pan) { return }
        playHapticPattern(patternType: preset.fallbackPattern)
    }

    public func playHapticPattern(patternType: String) {
        guard let engine = hapticEngine else {
            // Fallback to brief rumble pulse
            setRumble(left: 0.8, right: 0.8)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.setRumble(left: 0.0, right: 0.0)
            }
            return
        }
        
        do {
            var events: [CHHapticEvent] = []
            
            switch patternType {
            case "click":
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9)
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
                events.append(event)
                
            case "thud":
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: 0, duration: 0.25)
                events.append(event)
                
            case "heartbeat":
                let i1 = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7)
                let s1 = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                let e1 = CHHapticEvent(eventType: .hapticTransient, parameters: [i1, s1], relativeTime: 0)
                
                let i2 = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
                let s2 = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                let e2 = CHHapticEvent(eventType: .hapticTransient, parameters: [i2, s2], relativeTime: 0.18)
                events.append(contentsOf: [e1, e2])
                
            default:
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8)
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
                events.append(event)
            }
            
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("[Single Sense] CoreHaptics playback error: \(error)")
        }
    }
    
    public func applyProfile(_ profile: ControllerProfile) {
        self.lightbarConfig = profile.lightbar
        self.musicSyncConfig = profile.musicSync
        self.leftTriggerConfig = profile.leftTrigger.sanitized()
        self.rightTriggerConfig = profile.rightTrigger.sanitized()
        self.triggersLinked = profile.triggersLinked

        // Goes through the Music Sync path so the audio tap opens or closes
        // with the profile instead of keeping the previous one's state.
        applyMusicSyncConfiguration()
        applyTriggerConfiguration()
        // setRumble clamps, and it is what assigns the two intensity fields —
        // assigning them directly here would let an out-of-range profile value
        // reach the saturating byte conversion unchecked.
        setRumble(left: profile.leftRumble, right: profile.rightRumble)
    }
}
