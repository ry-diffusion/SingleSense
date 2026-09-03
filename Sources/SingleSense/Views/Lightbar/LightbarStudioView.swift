import SwiftUI

public struct LightbarStudioView: View {
    @ObservedObject var manager = DualSenseManager.shared
    // ControllerState is a reference type, so @Published on the manager never
    // fires for changes *inside* it. Observing it directly is what keeps live
    // input (trigger pressure, battery, telemetry) flowing into the view.
    @ObservedObject var controllerState = DualSenseManager.shared.controllerState
    @ObservedObject var rainbowEngine = RainbowEngine.shared

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
                                .font(.headline)
                            
                            Spacer()
                            
                            HStack(spacing: 12) {
                                Text("\(Int(controllerState.currentFPS)) FPS")
                                    .font(.subheadline.monospaced().weight(.bold))
                                    .foregroundColor(.green)
                                
                                Text(controllerState.currentLightbarColor.hexString)
                                    .font(.subheadline.monospaced().weight(.bold))
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
                        // A picture of the hex value announced above it.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Live lightbar colour")
                        .accessibilityValue(controllerState.currentLightbarColor.hexString)
                    }
                    .padding(16)
                }
                .frame(height: 90)
                
                if manager.musicSyncConfig.isDrivingLightbar {
                    musicSyncBanner
                }

                // Lighting Mode Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Lighting Mode")
                        .font(.headline.weight(.bold))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(LightingMode.selectable) { mode in
                            Button(action: {
                                manager.lightbarConfig.mode = mode
                                manager.applyLightbarConfiguration()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: mode.iconName)
                                        .font(.body)
                                        .foregroundColor(manager.lightbarConfig.mode == mode ? .white : .accentColor)
                                    
                                    Text(mode.rawValue)
                                        .font(.callout.weight(.semibold))
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
                                    .font(.headline.weight(.bold))
                                Spacer()
                                Text("Ultra-Smooth HSV Rotation")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            // Speed Slider
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Cycle Speed")
                                        .font(.callout.weight(.medium))
                                    Spacer()
                                    Text(String(format: "%.1fx", manager.lightbarConfig.rainbowSpeed))
                                        .font(.callout.monospaced().weight(.bold))
                                }
                                Slider(value: $manager.lightbarConfig.rainbowSpeed, in: 0.1...5.0, step: 0.1)
                            }
                            
                            // Saturation Slider
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Saturation")
                                        .font(.callout.weight(.medium))
                                    Spacer()
                                    Text("\(Int(manager.lightbarConfig.rainbowSaturation * 100))%")
                                        .font(.callout.monospaced().weight(.bold))
                                }
                                Slider(value: $manager.lightbarConfig.rainbowSaturation, in: 0.0...1.0)
                            }
                            
                            // Brightness Slider
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Brightness")
                                        .font(.callout.weight(.medium))
                                    Spacer()
                                    Text("\(Int(manager.lightbarConfig.rainbowBrightness * 100))%")
                                        .font(.callout.monospaced().weight(.bold))
                                }
                                Slider(value: $manager.lightbarConfig.rainbowBrightness, in: 0.0...1.0)
                            }
                        }
                        
                    case .staticColor, .breathing:
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(manager.lightbarConfig.mode == .breathing ? "Breathing Color & Rate" : "Static Color Customizer")
                                    .font(.headline.weight(.bold))
                                Spacer()
                                // Hex Field
                                HStack(spacing: 6) {
                                    Text("HEX:")
                                        .font(.subheadline.monospaced().weight(.bold))
                                        .foregroundColor(.secondary)
                                    TextField("#0066FF", text: $hexInput, onCommit: {
                                        manager.lightbarConfig.staticColor = RGBColor.fromHex(hexInput)
                                        manager.applyLightbarConfiguration()
                                    })
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 85)
                                    .font(.subheadline.monospaced())
                                }
                            }
                            
                            if manager.lightbarConfig.mode == .breathing {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Pulse Speed")
                                            .font(.callout.weight(.medium))
                                        Spacer()
                                        Text(String(format: "%.1fx", manager.lightbarConfig.breathingSpeed))
                                            .font(.callout.monospaced().weight(.bold))
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
                                .font(.callout.weight(.semibold))
                            
                            ColorPresetsGridView(selectedColor: $manager.lightbarConfig.staticColor) { newColor in
                                hexInput = newColor.hexString
                                manager.applyLightbarConfiguration()
                            }
                        }
                        
                    case .musicSync:
                        // Legacy mode, migrated away on load and absent from the
                        // grid above; Music Sync has its own section now.
                        EmptyView()

                    case .batteryReactive:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Battery Reactive Indicator")
                                .font(.headline.weight(.bold))
                            Text("The controller lightbar automatically shifts color based on battery health: 100% (Green) -> 50% (Yellow) -> 20% (Red) -> Low (Pulsing Red).")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        
                    case .triggerReactive:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Trigger Reactive Lighting")
                                .font(.headline.weight(.bold))
                            Text("Lightbar shifts from cool cyan to high-energy crimson red in real-time as you pull the L2 and R2 triggers.")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        
                    case .strobe:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Cyberpunk Strobe")
                                .font(.headline.weight(.bold))
                            Text("Rapidly cycles high-intensity neon hues (Cyan, Magenta, Yellow) at high frequency.")
                                .font(.callout)
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
                            .font(.headline.weight(.bold))
                        
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

                        if manager.musicSyncConfig.isDrivingPlayerLEDs {
                            Label("Music Sync is driving this row — the pattern above applies again when it stops.",
                                  systemImage: "waveform")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(12)
                    
                    // Mic LED Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Microphone LED")
                            .font(.headline.weight(.bold))
                        
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
                            .font(.subheadline)
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

    /// Music Sync overrides the mode below, so say so here rather than letting
    /// the grid look broken.
    @ViewBuilder
    private var musicSyncBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Music Sync is driving the light bar")
                    .font(.callout.weight(.semibold))
                Text("The mode you pick below takes over again when Music Sync stops driving it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
    }
}
