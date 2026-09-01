import SwiftUI

public struct TriggerStudioView: View {
    @ObservedObject var manager = DualSenseManager.shared
    // ControllerState is a reference type, so @Published on the manager never
    // fires for changes *inside* it. Observing it directly is what keeps live
    // input (trigger pressure, battery, telemetry) flowing into the view.
    @ObservedObject var controllerState = DualSenseManager.shared.controllerState
    @State var selectedTriggerIndex: Int = 0 // 0 = L2, 1 = R2
    
    public init() {}
    
    private var activeConfigBinding: Binding<SingleTriggerConfig> {
        if selectedTriggerIndex == 0 {
            return $manager.leftTriggerConfig
        } else {
            return $manager.rightTriggerConfig
        }
    }
    
    private var currentTriggerPosition: Float {
        selectedTriggerIndex == 0 ? controllerState.triggerL2 : controllerState.triggerR2
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Live Interactive Trigger Benchmark Header
                VStack(spacing: 12) {
                    HStack {
                        Label("Real-time Trigger Benchmark", systemImage: "gauge.with.needle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("Squeeze physical L2 / R2 to test active resistance")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 20) {
                        // L2 Real-time Live Bar
                        triggerLiveGauge(
                            label: "L2 TRIGGER",
                            value: controllerState.triggerL2,
                            config: manager.leftTriggerConfig,
                            isSelected: selectedTriggerIndex == 0
                        ) {
                            selectedTriggerIndex = 0
                        }
                        
                        // R2 Real-time Live Bar
                        triggerLiveGauge(
                            label: "R2 TRIGGER",
                            value: controllerState.triggerR2,
                            config: manager.rightTriggerConfig,
                            isSelected: selectedTriggerIndex == 1
                        ) {
                            selectedTriggerIndex = 1
                        }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
                
                // Interactive Dyno Test
                TriggerDynoTestCardView()
                
                // Trigger Selector & Link Toggle
                HStack {
                    Picker("Active Trigger", selection: $selectedTriggerIndex) {
                        Text("Left Trigger (L2)").tag(0)
                        Text("Right Trigger (R2)").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(maxWidth: 300)
                    
                    Spacer()
                    
                    Toggle("Link L2 & R2 Triggers", isOn: $manager.triggersLinked)
                        .toggleStyle(SwitchToggleStyle())
                        .onChange(of: manager.triggersLinked) { _ in
                            manager.applyTriggerConfiguration()
                        }
                }
                
                // Mode Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trigger Mode (\(selectedTriggerIndex == 0 ? "L2" : "R2"))")
                        .font(.system(size: 14, weight: .bold))
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                        ForEach(TriggerModeType.allCases) { mode in
                            Button(action: {
                                activeConfigBinding.wrappedValue.mode = mode
                                manager.applyTriggerConfiguration()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: mode.iconName)
                                        .font(.system(size: 13))
                                        .foregroundColor(activeConfigBinding.wrappedValue.mode == mode ? .white : .accentColor)
                                    
                                    Text(mode.rawValue)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(activeConfigBinding.wrappedValue.mode == mode ? .white : .primary)
                                    
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(activeConfigBinding.wrappedValue.mode == mode ? Color.accentColor : Color.secondary.opacity(0.1))
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(12)
                
                // Parameter Sliders for Active Mode
                VStack(alignment: .leading, spacing: 16) {
                    Text("Mode Parameters")
                        .font(.system(size: 14, weight: .bold))
                    
                    switch activeConfigBinding.wrappedValue.mode {
                    case .off:
                        Text("No resistance or haptic effect active on this trigger.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                    case .feedback:
                        VStack(spacing: 12) {
                            sliderRow(
                                title: "Start Position",
                                value: activeConfigBinding.startPosition,
                                format: "%.0f%%",
                                multiplier: 100
                            )
                            sliderRow(
                                title: "Resistive Force",
                                value: activeConfigBinding.strength,
                                format: "%.0f%%",
                                multiplier: 100
                            )
                        }
                        
                    case .weapon:
                        VStack(spacing: 12) {
                            sliderRow(
                                title: "Pre-Travel Start",
                                value: activeConfigBinding.startPosition,
                                format: "%.0f%%",
                                multiplier: 100
                            )
                            sliderRow(
                                title: "Break Threshold End",
                                value: activeConfigBinding.endPosition,
                                format: "%.0f%%",
                                multiplier: 100
                            )
                            sliderRow(
                                title: "Break Wall Force",
                                value: activeConfigBinding.strength,
                                format: "%.0f%%",
                                multiplier: 100
                            )
                        }
                        
                    case .vibration:
                        VStack(spacing: 12) {
                            sliderRow(
                                title: "Start Position",
                                value: activeConfigBinding.startPosition,
                                format: "%.0f%%",
                                multiplier: 100
                            )
                            sliderRow(
                                title: "Vibration Frequency",
                                value: activeConfigBinding.frequency,
                                range: 1...255,
                                format: "%.0f Hz",
                                multiplier: 1
                            )
                            sliderRow(
                                title: "Amplitude",
                                value: activeConfigBinding.amplitude,
                                format: "%.0f%%",
                                multiplier: 100
                            )
                        }
                        
                    case .slopeFeedback:
                        VStack(spacing: 12) {
                            sliderRow(
                                title: "Start Position",
                                value: activeConfigBinding.startPosition,
                                format: "%.0f%%",
                                multiplier: 100
                            )
                            sliderRow(
                                title: "End Position",
                                value: activeConfigBinding.endPosition,
                                format: "%.0f%%",
                                multiplier: 100
                            )
                            sliderRow(
                                title: "Start Force",
                                value: activeConfigBinding.startStrength,
                                format: "%.0f%%",
                                multiplier: 100
                            )
                            sliderRow(
                                title: "End Force",
                                value: activeConfigBinding.endStrength,
                                format: "%.0f%%",
                                multiplier: 100
                            )
                        }
                        
                    case .machineGun:
                        VStack(spacing: 12) {
                            sliderRow(
                                title: "Start Position",
                                value: activeConfigBinding.startPosition,
                                format: "%.0f%%",
                                multiplier: 100
                            )
                            sliderRow(
                                title: "Pulse Recoil Force",
                                value: activeConfigBinding.strength,
                                format: "%.0f%%",
                                multiplier: 100
                            )
                        }
                        
                    case .customCurve:
                        TriggerZoneGraphView(
                            zones: activeConfigBinding.custom10Zones,
                            currentTriggerPosition: currentTriggerPosition,
                            isVibration: false
                        ) {
                            manager.applyTriggerConfiguration()
                        }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(12)
                
                // Weapon Presets Section
                TriggerPresetsView { preset in
                    manager.leftTriggerConfig = preset.leftConfig
                    manager.rightTriggerConfig = preset.rightConfig
                    manager.applyTriggerConfiguration()
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - Subviews
    private func triggerLiveGauge(
        label: String,
        value: Float,
        config: SingleTriggerConfig,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                Spacer()
                Text(config.mode.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("\(Int(value * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
            
            // Progress Bar with Resistance Zone
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 22)
                
                // Active Mode Zone Overlay
                if config.mode != .off {
                    GeometryReader { geo in
                        let start = CGFloat(config.startPosition) * geo.size.width
                        let width = CGFloat(max(0.1, config.endPosition - config.startPosition)) * geo.size.width
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.orange.opacity(0.25))
                            .frame(width: width, height: 18)
                            .offset(x: start, y: 2)
                    }
                }
                
                // Current Pull Level
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: isSelected ? [.blue, .cyan] : [.secondary.opacity(0.6), .secondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(value), height: 22)
                }
            }
            .frame(height: 22)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
    
    private func sliderRow(
        title: String,
        value: Binding<Float>,
        range: ClosedRange<Float> = 0.0...1.0,
        format: String,
        multiplier: Float
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(String(format: format, value.wrappedValue * multiplier))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            Slider(value: value, in: range) { _ in
                manager.applyTriggerConfiguration()
            }
        }
    }
}
