import SwiftUI

public struct LightbarStudioView: View {
    @ObservedObject var manager = DualSenseManager.shared
    // ControllerState is a reference type, so @Published on the manager never
    // fires for changes *inside* it. Observing it directly is what keeps live
    // input (trigger pressure, battery, telemetry) flowing into the view.
    @ObservedObject var controllerState = DualSenseManager.shared.controllerState
    @ObservedObject var rainbowEngine = RainbowEngine.shared
    @ObservedObject var audioEngine = AudioReactiveEngine.shared
    
    @State private var hexInput: String = ""
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Live Lightbar Glow Banner
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(controllerState.currentLightbarColor.color.opacity(0.4), lineWidth: 1.5)
                        )
                        .shadow(color: controllerState.currentLightbarColor.color.opacity(0.3), radius: 12)
                    
                    VStack(spacing: 12) {
                        HStack {
                            Label("Live Lightbar Output", systemImage: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                            
                            Spacer()
                            
                            HStack(spacing: 12) {
                                Text("\(Int(controllerState.currentFPS)) FPS")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.green)
                                
                                Text(controllerState.currentLightbarColor.hexString)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Center Glowing Strip
                        ZStack {
                            Capsule()
                                .fill(Color.black.opacity(0.4))
                                .frame(height: 16)
                            
                            Capsule()
                                .fill(controllerState.currentLightbarColor.color)
                                .frame(height: 12)
                                .shadow(color: controllerState.currentLightbarColor.color, radius: 10)
                        }
                    }
                    .padding(16)
                }
                .frame(height: 90)
                
                // Lighting Mode Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Lighting Mode")
                        .font(.system(size: 14, weight: .bold))
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(LightingMode.allCases) { mode in
                            Button(action: {
                                manager.lightbarConfig.mode = mode
                                manager.applyLightbarConfiguration()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: mode.iconName)
                                        .font(.system(size: 14))
                                        .foregroundColor(manager.lightbarConfig.mode == mode ? .white : .accentColor)
                                    
                                    Text(mode.rawValue)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(manager.lightbarConfig.mode == mode ? .white : .primary)
                                    
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(manager.lightbarConfig.mode == mode ? Color.accentColor : Color.secondary.opacity(0.1))
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(12)
                
                // Mode-Specific Settings
                VStack(alignment: .leading, spacing: 16) {
                    switch manager.lightbarConfig.mode {
                    case .rainbow:
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("60 FPS Rainbow Settings")
                                    .font(.system(size: 14, weight: .bold))
                                Spacer()
                                Text("Ultra-Smooth HSV Rotation")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            // Speed Slider
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Cycle Speed")
                                        .font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    Text(String(format: "%.1fx", manager.lightbarConfig.rainbowSpeed))
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                }
                                Slider(value: $manager.lightbarConfig.rainbowSpeed, in: 0.1...5.0, step: 0.1)
                            }
                            
                            // Saturation Slider
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Saturation")
                                        .font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    Text("\(Int(manager.lightbarConfig.rainbowSaturation * 100))%")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                }
                                Slider(value: $manager.lightbarConfig.rainbowSaturation, in: 0.0...1.0)
                            }
                            
                            // Brightness Slider
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Brightness")
                                        .font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    Text("\(Int(manager.lightbarConfig.rainbowBrightness * 100))%")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                }
                                Slider(value: $manager.lightbarConfig.rainbowBrightness, in: 0.0...1.0)
                            }
                        }
                        
                    case .staticColor, .breathing:
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(manager.lightbarConfig.mode == .breathing ? "Breathing Color & Rate" : "Static Color Customizer")
                                    .font(.system(size: 14, weight: .bold))
                                Spacer()
                                // Hex Field
                                HStack(spacing: 6) {
                                    Text("HEX:")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    TextField("#0066FF", text: $hexInput, onCommit: {
                                        manager.lightbarConfig.staticColor = RGBColor.fromHex(hexInput)
                                        manager.applyLightbarConfiguration()
                                    })
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 85)
                                    .font(.system(size: 11, design: .monospaced))
                                }
                            }
                            
                            if manager.lightbarConfig.mode == .breathing {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Pulse Speed")
                                            .font(.system(size: 12, weight: .medium))
                                        Spacer()
                                        Text(String(format: "%.1fx", manager.lightbarConfig.breathingSpeed))
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    }
                                    Slider(value: $manager.lightbarConfig.breathingSpeed, in: 0.2...4.0, step: 0.1)
                                }
                                Divider()
                            }
                            
                            RGBColorSlidersView(color: $manager.lightbarConfig.staticColor) { _ in
                                hexInput = manager.lightbarConfig.staticColor.hexString
                                manager.applyLightbarConfiguration()
                            }
                            
                            Divider()
                            
                            Text("Color Presets")
                                .font(.system(size: 12, weight: .semibold))
                            
                            ColorPresetsGridView(selectedColor: $manager.lightbarConfig.staticColor) { newColor in
                                hexInput = newColor.hexString
                                manager.applyLightbarConfiguration()
                            }
                        }
                        
                    case .musicSync:
                        musicSyncSettings

                    case .batteryReactive:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Battery Reactive Indicator")
                                .font(.system(size: 14, weight: .bold))
                            Text("The controller lightbar automatically shifts color based on battery health: 100% (Green) -> 50% (Yellow) -> 20% (Red) -> Low (Pulsing Red).")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                    case .triggerReactive:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Trigger Reactive Lighting")
                                .font(.system(size: 14, weight: .bold))
                            Text("Lightbar shifts from cool cyan to high-energy crimson red in real-time as you pull the L2 and R2 triggers.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                    case .strobe:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Cyberpunk Strobe")
                                .font(.system(size: 14, weight: .bold))
                            Text("Rapidly cycles high-intensity neon hues (Cyan, Magenta, Yellow) at high frequency.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(12)
                
                // Player LEDs & Microphone LED Control
                HStack(alignment: .top, spacing: 16) {
                    // Player LEDs Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Player Indicator LEDs")
                            .font(.system(size: 13, weight: .bold))
                        
                        Picker("Player Pattern", selection: $manager.lightbarConfig.playerLEDMode) {
                            ForEach(PlayerLEDMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: manager.lightbarConfig.playerLEDMode) { _ in
                            manager.applyLightbarConfiguration()
                        }
                        
                        Picker("LED Brightness", selection: $manager.lightbarConfig.playerLEDBrightness) {
                            ForEach(PlayerLEDBrightness.allCases) { brightness in
                                Text(brightness.rawValue).tag(brightness)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .onChange(of: manager.lightbarConfig.playerLEDBrightness) { _ in
                            manager.applyLightbarConfiguration()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(12)
                    
                    // Mic LED Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Microphone LED")
                            .font(.system(size: 13, weight: .bold))
                        
                        Picker("Mic LED State", selection: $manager.lightbarConfig.micLEDMode) {
                            ForEach(MicLEDMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .onChange(of: manager.lightbarConfig.micLEDMode) { _ in
                            manager.applyLightbarConfiguration()
                        }
                        
                        Text("Controls the small orange LED on the mute button below the PS logo.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(12)
                }
            }
            .padding(20)
        }
        .onAppear {
            hexInput = manager.lightbarConfig.staticColor.hexString
        }
    }

    // MARK: - Music Sync

    @ViewBuilder
    private var musicSyncSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Music Sync")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                captureStatusBadge
            }

            Text("Reads the system audio mix through ScreenCaptureKit, so it follows whatever is playing — Spotify, Apple Music, a browser tab or a game.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if case .permissionRequired = audioEngine.status {
                permissionCallout
            }
            if case .failed(let message) = audioEngine.status {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text("Style")
                .font(.system(size: 12, weight: .semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 10)], spacing: 10) {
                ForEach(MusicSyncStyle.allCases) { style in
                    let selected = manager.lightbarConfig.musicSyncStyle == style
                    Button(action: {
                        manager.lightbarConfig.musicSyncStyle = style
                        manager.applyLightbarConfiguration()
                    }) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(style.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(selected ? .white : .primary)
                            Text(style.detail)
                                .font(.system(size: 10))
                                .foregroundColor(selected ? .white.opacity(0.85) : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selected ? Color.accentColor : Color.secondary.opacity(0.1))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            Divider()

            HStack {
                Text("Player Indicator Row")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                indicatorPreview
            }

            Picker("", selection: $manager.lightbarConfig.playerLEDAudioStyle) {
                ForEach(PlayerLEDAudioStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()
            .onChange(of: manager.lightbarConfig.playerLEDAudioStyle) { _ in
                manager.applyLightbarConfiguration()
            }

            Text(manager.lightbarConfig.playerLEDAudioStyle.detail)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Divider()

            HStack {
                Text("Haptics")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                motorPreview
            }

            Picker("", selection: $manager.lightbarConfig.musicHapticsStyle) {
                ForEach(MusicHapticsStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()
            .onChange(of: manager.lightbarConfig.musicHapticsStyle) { _ in
                manager.applyLightbarConfiguration()
            }

            Text(manager.lightbarConfig.musicHapticsStyle.detail)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            if manager.lightbarConfig.musicHapticsStyle != .off {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Rumble Intensity")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(Int(manager.lightbarConfig.musicHapticsIntensity * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    Slider(value: $manager.lightbarConfig.musicHapticsIntensity, in: 0.0...1.0) { _ in
                        manager.applyLightbarConfiguration()
                    }
                }

                Label("Continuous rumble drains the controller noticeably faster.",
                      systemImage: "battery.25")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Divider()

            Text("Live Spectrum")
                .font(.system(size: 12, weight: .semibold))
            spectrumMeters

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Sensitivity")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(String(format: "%.2fx", manager.lightbarConfig.audioSensitivity))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                Slider(value: $manager.lightbarConfig.audioSensitivity, in: 0.25...4.0, step: 0.05) { _ in
                    manager.applyLightbarConfiguration()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Smoothing")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(Int(manager.lightbarConfig.audioSmoothing * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                Slider(value: $manager.lightbarConfig.audioSmoothing, in: 0.0...1.0) { _ in
                    manager.applyLightbarConfiguration()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Floor Brightness")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(Int(manager.lightbarConfig.audioMinimumBrightness * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                Slider(value: $manager.lightbarConfig.audioMinimumBrightness, in: 0.0...0.5)
            }

            if manager.lightbarConfig.musicSyncStyle == .pulse
                || manager.lightbarConfig.musicSyncStyle == .beatFlash {
                Divider()
                Text("Base Color")
                    .font(.system(size: 12, weight: .semibold))
                RGBColorSlidersView(color: $manager.lightbarConfig.staticColor) { _ in
                    hexInput = manager.lightbarConfig.staticColor.hexString
                }
                ColorPresetsGridView(selectedColor: $manager.lightbarConfig.staticColor) { newColor in
                    hexInput = newColor.hexString
                }
            }
        }
    }

    @ViewBuilder
    private var captureStatusBadge: some View {
        let descriptor: (String, Color) = {
            switch audioEngine.status {
            case .idle: return ("Idle", .secondary)
            case .starting: return ("Starting…", .orange)
            case .running: return ("Listening", .green)
            case .permissionRequired: return ("Permission needed", .orange)
            case .failed: return ("Error", .red)
            }
        }()

        HStack(spacing: 5) {
            Circle().fill(descriptor.1).frame(width: 7, height: 7)
            Text(descriptor.0)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(descriptor.1)
        }
    }

    @ViewBuilder
    private var permissionCallout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "SingleSense needs Screen Recording permission to read the system audio mix. No video is captured or stored.",
                systemImage: "lock.shield"
            )
            .font(.system(size: 11))
            .fixedSize(horizontal: false, vertical: true)

            Button("Open Privacy Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    /// Mirrors the row the controller is showing, resolved through the very
    /// same function that fills the output report.
    @ViewBuilder
    private var indicatorPreview: some View {
        let levels = audioEngine.displayLevels
        let mask = manager.lightbarConfig.playerLEDMask(level: levels.overall, beat: levels.beat)
        HStack(spacing: 5) {
            ForEach(0..<PlayerLEDIndicator.lampCount, id: \.self) { index in
                let lit = (mask >> UInt8(index)) & 1 == 1
                Circle()
                    .fill(lit ? Color.white : Color.secondary.opacity(0.22))
                    .frame(width: 8, height: 8)
                    .shadow(color: lit ? .white.opacity(0.8) : .clear, radius: 3)
            }
        }
    }

    /// Live motor levels, resolved through the same function that fills the
    /// rumble bytes in the output report.
    @ViewBuilder
    private var motorPreview: some View {
        let levels = audioEngine.displayLevels
        let motors = manager.lightbarConfig.musicRumble(
            bass: levels.bass, mid: levels.mid, treble: levels.treble, beat: levels.beat
        )
        HStack(spacing: 8) {
            motorPip("L", motors.left)
            motorPip("R", motors.right)
        }
    }

    private func motorPip(_ label: String, _ value: Float) -> some View {
        let clamped = CGFloat(max(0, min(1, value)))
        return HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18)).frame(width: 34, height: 6)
                Capsule().fill(Color.orange).frame(width: 34 * clamped, height: 6)
            }
        }
    }

    @ViewBuilder
    private var spectrumMeters: some View {
        let levels = audioEngine.displayLevels
        VStack(spacing: 6) {
            meterRow("Bass", levels.bass, .red)
            meterRow("Mid", levels.mid, .green)
            meterRow("Treble", levels.treble, .blue)
            meterRow("Beat", levels.beat, .purple)
        }
    }

    private func meterRow(_ title: String, _ value: Float, _ tint: Color) -> some View {
        let clamped = CGFloat(max(0, min(1, value)))
        return HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 46, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(tint).frame(width: clamped * geo.size.width)
                }
            }
            .frame(height: 8)
            Text("\(Int(clamped * 100))%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }

}
