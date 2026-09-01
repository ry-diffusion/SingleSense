import SwiftUI

public struct DashboardView: View {
    @ObservedObject var manager = DualSenseManager.shared
    // ControllerState is a reference type, so @Published on the manager never
    // fires for changes *inside* it. Observing it directly is what keeps live
    // input (trigger pressure, battery, telemetry) flowing into the view.
    @ObservedObject var controllerState = DualSenseManager.shared.controllerState
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Top Status Header Card
                HStack(alignment: .center, spacing: 16) {
                    // Controller Glyph & Model
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 28))
                        .foregroundColor(controllerState.isConnected ? .accentColor : .secondary)
                        .frame(width: 48, height: 48)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(10)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(controllerState.model.rawValue)
                            .font(.system(size: 15, weight: .bold))
                        
                        Text(controllerState.isConnected ? "Active & Synchronized" : "Connect DualSense via USB or Bluetooth")
                            .font(.system(size: 12))
                            .foregroundColor(controllerState.isConnected ? .green : .secondary)
                    }
                    
                    Spacer()
                    
                    // Connection Badge & Battery
                    ConnectionBadgeView(
                        isConnected: controllerState.isConnected,
                        type: controllerState.connectionType,
                        modelName: controllerState.model.shortName
                    )
                    
                    if controllerState.isConnected {
                        BatteryIndicatorView(
                            level: controllerState.batteryLevel,
                            isCharging: controllerState.isBatteryCharging
                        )
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                
                // Live Gamepad Visualizer
                GamepadVisualizerView(state: controllerState)
                
                // Interactive Trigger & Haptic Dyno Test Feature Card
                TriggerDynoTestCardView()
                
                // Quick Control & Customization Bar
                VStack(alignment: .leading, spacing: 14) {
                    Text("Quick Controls")
                        .font(.system(size: 14, weight: .bold))
                    
                    HStack(spacing: 12) {
                        // Rainbow Toggle
                        Button(action: {
                            if manager.lightbarConfig.mode == .rainbow {
                                manager.lightbarConfig.mode = .staticColor
                            } else {
                                manager.lightbarConfig.mode = .rainbow
                            }
                            manager.applyLightbarConfiguration()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "rainbow")
                                Text(manager.lightbarConfig.mode == .rainbow ? "Rainbow: ON" : "Rainbow: OFF")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(manager.lightbarConfig.mode == .rainbow ? Color.accentColor : Color.secondary.opacity(0.12))
                            .foregroundColor(manager.lightbarConfig.mode == .rainbow ? .white : .primary)
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Weapon Quick Preset: Desert Eagle
                        Button(action: {
                            if let preset = TriggerPresets.all.first(where: { $0.id == "desert_eagle" }) {
                                manager.leftTriggerConfig = preset.leftConfig
                                manager.rightTriggerConfig = preset.rightConfig
                                manager.applyTriggerConfiguration()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "scope")
                                Text("Gun Preset")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Standard Triggers Reset
                        Button(action: {
                            manager.leftTriggerConfig.mode = .off
                            manager.rightTriggerConfig.mode = .off
                            manager.applyTriggerConfiguration()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset Triggers")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Quick Haptic Pulse Test
                        Button(action: {
                            manager.playHapticPattern(patternType: "click")
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform.path")
                                Text("Test Haptic")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(12)
            }
            .padding(20)
        }
    }
}
