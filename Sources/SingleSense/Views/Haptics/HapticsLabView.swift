import SwiftUI

public struct HapticsLabView: View {
    @ObservedObject var manager = DualSenseManager.shared
    @State private var syncMotors: Bool = false
    @State private var isTestContinuousActive: Bool = false
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header & Waveform Animation
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                        )
                    
                    VStack(spacing: 12) {
                        HStack {
                            Label("Haptics & Motor Lab", systemImage: "waveform.path.ecg")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if manager.leftRumbleIntensity > 0 || manager.rightRumbleIntensity > 0 {
                                Button("Stop Vibration") {
                                    manager.setRumble(left: 0, right: 0)
                                }
                                .buttonStyle(BorderedProminentButtonStyle())
                                .tint(.red)
                            }
                        }
                        
                        // Animated Waveform Indicator
                        HStack(alignment: .center, spacing: 4) {
                            ForEach(0..<24, id: \.self) { index in
                                let combined = CGFloat(max(manager.leftRumbleIntensity, manager.rightRumbleIntensity))
                                let height = max(4, combined * CGFloat(sin(Double(index) * 0.4) * 20.0 + 24.0))
                                
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .cyan],
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .frame(width: 6, height: height)
                            }
                        }
                        .frame(height: 50)
                    }
                    .padding(16)
                }
                
                // Interactive Dyno Test
                TriggerDynoTestCardView()
                
                // Rumble Motor Controls
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Dual Rumble Motors")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                        Toggle("Sync Motors", isOn: $syncMotors)
                            .toggleStyle(SwitchToggleStyle())
                    }
                    
                    // Left Motor (Heavy low-frequency weight)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Left Motor (Heavy / Low Frequency)", systemImage: "speaker.wave.3.fill")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(Int(manager.leftRumbleIntensity * 100))%  (\(UInt8(manager.leftRumbleIntensity * 255)))")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                        Slider(
                            value: Binding(
                                get: { manager.leftRumbleIntensity },
                                set: { newValue in
                                    if syncMotors {
                                        manager.setRumble(left: newValue, right: newValue)
                                    } else {
                                        manager.setRumble(left: newValue, right: manager.rightRumbleIntensity)
                                    }
                                }
                            ),
                            in: 0.0...1.0
                        )
                    }
                    
                    Divider()
                    
                    // Right Motor (Light high-frequency weight)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Right Motor (Light / High Frequency)", systemImage: "speaker.wave.2.fill")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(Int(manager.rightRumbleIntensity * 100))%  (\(UInt8(manager.rightRumbleIntensity * 255)))")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                        Slider(
                            value: Binding(
                                get: { manager.rightRumbleIntensity },
                                set: { newValue in
                                    if syncMotors {
                                        manager.setRumble(left: newValue, right: newValue)
                                    } else {
                                        manager.setRumble(left: manager.leftRumbleIntensity, right: newValue)
                                    }
                                }
                            ),
                            in: 0.0...1.0
                        )
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(12)
                
                // CoreHaptics Sensory Patterns
                VStack(alignment: .leading, spacing: 14) {
                    Text("CoreHaptics Sensory Presets")
                        .font(.system(size: 14, weight: .bold))
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                        hapticButton(name: "Crisp Click", icon: "hand.tap.fill", pattern: "click")
                        hapticButton(name: "Heavy Thud", icon: "arrow.down.to.line.compact", pattern: "thud")
                        hapticButton(name: "Heartbeat Pulse", icon: "heart.fill", pattern: "heartbeat")
                        hapticButton(name: "Rapid Burst", icon: "burst.fill", pattern: "burst")
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(12)
            }
            .padding(20)
        }
    }
    
    private func hapticButton(name: String, icon: String, pattern: String) -> some View {
        Button(action: {
            manager.playHapticPattern(patternType: pattern)
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
