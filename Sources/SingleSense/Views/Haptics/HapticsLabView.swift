import SwiftUI

public struct HapticsLabView: View {
    @ObservedObject var manager = DualSenseManager.shared
    @ObservedObject var coils = VoiceCoilEngine.shared
    @State private var syncMotors: Bool = false
    @State private var coilPan: Float = 0
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
                                .font(.headline)
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
                            .font(.headline.weight(.bold))
                        Spacer()
                        Toggle("Sync Motors", isOn: $syncMotors)
                            .toggleStyle(SwitchToggleStyle())
                    }
                    
                    // Left Motor (Heavy low-frequency weight)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Left Motor (Heavy / Low Frequency)", systemImage: "speaker.wave.3.fill")
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text("\(Int(manager.leftRumbleIntensity * 100))%  (\(UInt8(manager.leftRumbleIntensity * 255)))")
                                .font(.callout.monospaced().weight(.bold))
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
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text("\(Int(manager.rightRumbleIntensity * 100))%  (\(UInt8(manager.rightRumbleIntensity * 255)))")
                                .font(.callout.monospaced().weight(.bold))
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
                
                voiceCoilSection
            }
            .padding(20)
        }
    }
    
    // MARK: - Voice coils

    private var voiceCoilSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Voice-Coil Haptics")
                    .font(.headline.weight(.bold))
                Spacer()
                coilStatusBadge
            }

            Text(coils.status.canPlay
                 ? "Waveforms played straight into the two actuators in the grips — the same hardware the motors only imitate, so clicks are sharp, textures have grain and each grip can do something different."
                 : "Over USB these play straight into the actuators in the grips. Without the cable they fall back to CoreHaptics, and the effects marked with a dot are only approximated.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                ForEach(HapticPreset.allCases) { preset in
                    hapticButton(preset)
                }
            }

            HStack(spacing: 14) {
                Text("Grip")
                    .font(.callout.weight(.medium))
                Picker("Grip", selection: $coilPan) {
                    Text("Left").tag(Float(-1))
                    Text("Both").tag(Float(0))
                    Text("Right").tag(Float(1))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)

                Text("Strength")
                    .font(.callout.weight(.medium))
                Slider(value: $coils.strength, in: 0.1...1)
                    .accessibilityLabel("Voice-coil strength")
                Text("\(Int((coils.strength * 100).rounded()))%")
                    .font(.callout.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .disabled(!coils.status.canPlay)
            .opacity(coils.status.canPlay ? 1 : 0.55)

            if case .failed(let message) = coils.status {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    private var coilStatusBadge: some View {
        let descriptor: (String, Color) = {
            switch coils.status {
            case .unavailable: return ("USB only — using CoreHaptics", .secondary)
            case .ready: return ("Ready", .green)
            case .running: return ("Active", .green)
            case .failed: return ("Error", .red)
            }
        }()
        return HStack(spacing: 5) {
            Circle().fill(descriptor.1).frame(width: 7, height: 7)
            Text(descriptor.0)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(descriptor.1)
        }
    }

    private func hapticButton(_ preset: HapticPreset) -> some View {
        Button(action: {
            manager.playHaptic(preset, pan: coilPan)
        }) {
            HStack(spacing: 8) {
                Image(systemName: preset.iconName)
                    .font(.body)
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
                Text(preset.rawValue)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
                if preset.needsVoiceCoils && !coils.status.canPlay {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("approximated without the voice coils")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
