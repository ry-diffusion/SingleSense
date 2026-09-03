import Foundation
import Combine

public final class RainbowEngine: ObservableObject {
    public static let shared = RainbowEngine()
    
    private var timer: Timer?
    private var startTime: Date = Date()
    private var frameCount: UInt64 = 0
    private var lastFpsCalculationTime: Date = Date()
    private var calculatedFPS: Double = 60.0
    
    public var onColorTick: ((RGBColor) -> Void)?
    
    @Published public var currentDisplayColor: RGBColor = RGBColor(red: 0.0, green: 0.38, blue: 1.0)
    
    private init() {}
    
    public func start() {
        stop()
        startTime = Date()
        lastFpsCalculationTime = Date()
        frameCount = 0
        
        // 60 FPS timer (approx 16.6ms interval)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private func tick() {
        let now = Date()
        let elapsed = now.timeIntervalSince(startTime)
        frameCount += 1
        
        // Update FPS counter every second
        let fpsElapsed = now.timeIntervalSince(lastFpsCalculationTime)
        if fpsElapsed >= 1.0 {
            calculatedFPS = Double(frameCount) / fpsElapsed
            frameCount = 0
            lastFpsCalculationTime = now
            let measured = calculatedFPS
            publishOnNextRunLoopTurn {
                DualSenseManager.shared.controllerState.currentFPS = measured
            }
        }
        
        guard let onColorTick = self.onColorTick else { return }
        let manager = DualSenseManager.shared
        // Nothing to drive without a controller, and every tick otherwise
        // republishes @Published state that the whole UI observes.
        guard manager.controllerState.isConnected else { return }
        let config = manager.lightbarConfig
        let music = manager.musicSyncConfig

        // If in static color mode and not in dynamic test, avoid streaming 60 identical packets/sec.
        // Music Sync has to keep the frames coming even from a static mode: the
        // indicator row and the rumble bytes travel in the same report, so
        // skipping the frame would freeze them mid-track.
        if config.mode == .staticColor && !music.needsContinuousOutput && !manager.isTriggerDynoTestActive {
            if currentDisplayColor != config.staticColor {
                let colour = config.staticColor
                publishOnNextRunLoopTurn { [weak self] in
                    self?.currentDisplayColor = colour
                }
                onColorTick(colour)
            }
            return
        }
        
        let nextColor = calculateColor(for: config, music: music, elapsed: elapsed)
        publishOnNextRunLoopTurn { [weak self] in
            self?.currentDisplayColor = nextColor
        }
        onColorTick(nextColor)
    }
    
    /// Maps the current audio analysis onto a lightbar colour.
    ///
    /// `base` is the colour the styles that need one tint from — the same
    /// static colour the light bar uses outside Music Sync.
    private func musicSyncColor(for music: MusicSyncConfiguration, base: RGBColor) -> RGBColor {
        let levels = AudioReactiveEngine.shared.levels
        let floor = max(0, min(1, music.minimumBrightness))

        switch music.lightbarStyle {
        case .spectrum:
            // Each band drives its own channel, lifted off zero so the bar
            // never goes fully dark between phrases.
            return RGBColor(
                red: Double(levels.bass) * (1 - floor) + floor * 0.2,
                green: Double(levels.mid) * (1 - floor) + floor * 0.2,
                blue: Double(levels.treble) * (1 - floor) + floor * 0.2
            )

        case .pulse:
            let brightness = floor + Double(levels.overall) * (1 - floor)
            return RGBColor(
                red: base.red * brightness,
                green: base.green * brightness,
                blue: base.blue * brightness
            )

        case .hueShift:
            // Where the energy sits decides the hue: bass-dominant material
            // lands at red, treble-dominant at cyan.
            let total = levels.bass + levels.mid + levels.treble
            let balance = total > 0.001
                ? Double((levels.mid * 0.5 + levels.treble) / total)
                : 0.0
            let brightness = floor + Double(levels.overall) * (1 - floor)
            return RGBColor.fromHSV(hue: balance * 0.5, saturation: 1.0, value: brightness)

        case .beatFlash:
            let brightness = floor + Double(levels.beat) * (1 - floor)
            return RGBColor(
                red: base.red * brightness,
                green: base.green * brightness,
                blue: base.blue * brightness
            )
        }
    }

    public func calculateColor(
        for config: LightbarConfiguration,
        music: MusicSyncConfiguration = MusicSyncConfiguration(),
        elapsed: TimeInterval,
        controllerState: ControllerState? = nil
    ) -> RGBColor {
        // Music Sync takes the bar over from whatever mode is selected, so the
        // mode stays as the user left it and comes back when the music stops.
        if music.isDrivingLightbar {
            return musicSyncColor(for: music, base: config.staticColor)
        }

        switch config.mode {
        case .staticColor:
            return config.staticColor
            
        case .rainbow:
            // Smooth HSV to RGB cycle inspired by dualsense-rainbow
            let speed = config.rainbowSpeed
            let hue = (elapsed * 0.2 * speed).truncatingRemainder(dividingBy: 1.0)
            return RGBColor.fromHSV(
                hue: hue,
                saturation: config.rainbowSaturation,
                value: config.rainbowBrightness
            )
            
        case .breathing:
            let speed = config.breathingSpeed
            // Sine wave breathing between 0.15 and 1.0 brightness
            let wave = (sin(elapsed * speed * .pi) + 1.0) / 2.0
            let brightness = 0.15 + (wave * 0.85)
            return RGBColor(
                red: config.staticColor.red * brightness,
                green: config.staticColor.green * brightness,
                blue: config.staticColor.blue * brightness
            )
            
        case .batteryReactive:
            let state = controllerState ?? DualSenseManager.shared.controllerState
            let battery = Double(state.batteryLevel)
            if battery > 0.5 {
                // Green to Yellow transition
                let t = (battery - 0.5) * 2.0
                return RGBColor(red: 1.0 - t, green: 1.0, blue: 0.0)
            } else if battery > 0.2 {
                // Yellow to Red transition
                let t = (battery - 0.2) / 0.3
                return RGBColor(red: 1.0, green: t, blue: 0.0)
            } else {
                // Red pulse for low battery
                let wave = (sin(elapsed * 4.0 * .pi) + 1.0) / 2.0
                return RGBColor(red: 0.4 + 0.6 * wave, green: 0.0, blue: 0.0)
            }
            
        case .triggerReactive:
            let state = controllerState ?? DualSenseManager.shared.controllerState
            let l2 = Double(state.triggerL2)
            let r2 = Double(state.triggerR2)
            let maxTrigger = max(l2, r2)
            
            // Hue shifts smoothly: Green (0.333) -> Yellow (0.166) -> Orange -> Red (0.0)
            let hue = 0.333 * (1.0 - maxTrigger)
            return RGBColor.fromHSV(hue: hue, saturation: 1.0, value: 1.0)
            
        case .musicSync:
            // Legacy mode, migrated away on load. Reaching it means the music
            // is not driving the bar, so there is nothing to react to.
            return config.staticColor

        case .strobe:
            // High-energy strobe flash every 0.1s
            let isStrobeOn = (Int(elapsed * 10) % 2) == 0
            if isStrobeOn {
                return config.staticColor
            } else {
                return RGBColor(red: 0.0, green: 0.0, blue: 0.0)
            }
        }
    }
}
