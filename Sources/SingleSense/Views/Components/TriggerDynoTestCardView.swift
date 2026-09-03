import SwiftUI

public struct TriggerDynoTestCardView: View {
    @ObservedObject var manager = DualSenseManager.shared
    // ControllerState is a reference type, so @Published on the manager never
    // fires for changes *inside* it. Observing it directly is what keeps live
    // input (trigger pressure, battery, telemetry) flowing into the view.
    @ObservedObject var controllerState = DualSenseManager.shared.controllerState
    
    public init() {}
    
    private var activeTriggerValue: Float {
        max(controllerState.triggerL2, controllerState.triggerR2)
    }
    
    private var vibrationFrequencyHz: Int {
        Int(activeTriggerValue * 200.0)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with Test Switch
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.title2)
                        .foregroundColor(manager.isTriggerDynoTestActive ? .green : .accentColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Interactive Trigger & Haptic Dyno Test")
                            .font(.headline.weight(.bold))
                        
                        Text("Squeeze L2 or R2: the colour sweeps from green to red and the rumble speeds up with your finger.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Toggle Button
                Button(action: {
                    manager.toggleTriggerDynoTest()
                }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(manager.isTriggerDynoTestActive ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 8, height: 8)
                        
                        Text(manager.isTriggerDynoTestActive ? "Dyno Test: ACTIVE" : "Start Dyno Test")
                            .font(.callout.weight(.bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(manager.isTriggerDynoTestActive ? Color.green.opacity(0.2) : Color.secondary.opacity(0.12))
                    .foregroundColor(manager.isTriggerDynoTestActive ? .green : .primary)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(manager.isTriggerDynoTestActive ? Color.green : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if manager.isTriggerDynoTestActive {
                VStack(spacing: 12) {
                    // Gauge 1: Green -> Yellow -> Red Spectrum Bar
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Lightbar Colour Spectrum (Green → Red)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(String(format: "%.0f%% pressure", activeTriggerValue * 100))
                                .font(.subheadline.monospaced().weight(.bold))
                                .foregroundColor(controllerState.currentLightbarColor.color)
                        }
                        
                        ZStack(alignment: .leading) {
                            // Background Spectrum Gradient
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.0, green: 1.0, blue: 0.0), // green
                                            Color(red: 1.0, green: 1.0, blue: 0.0), // yellow
                                            Color(red: 1.0, green: 0.5, blue: 0.0), // orange
                                            Color(red: 1.0, green: 0.0, blue: 0.0)  // red
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(height: 24)
                            
                            // Live Cursor Indicator
                            GeometryReader { geo in
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 20, height: 20)
                                        .shadow(color: Color.black.opacity(0.4), radius: 4)
                                    
                                    Circle()
                                        .fill(controllerState.currentLightbarColor.color)
                                        .frame(width: 14, height: 14)
                                }
                                .position(
                                    x: max(10, min(geo.size.width - 10, geo.size.width * CGFloat(activeTriggerValue))),
                                    y: 12
                                )
                            }
                            .frame(height: 24)
                        }
                        .frame(height: 24)
                    }
                    
                    // Gauge 2: Real-time Vibration Speed & Frequency
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Rumble / Haptic Speed")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(activeTriggerValue > 0.03 ? "\(vibrationFrequencyHz) Hz / \(Int(activeTriggerValue * 100))% Rumble" : "Silent (0 Hz)")
                                .font(.subheadline.monospaced().weight(.bold))
                                .foregroundColor(activeTriggerValue > 0.03 ? .orange : .secondary)
                        }
                        
                        // Animated Vibration Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.15))
                                
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        LinearGradient(
                                            colors: [.orange, .red],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * CGFloat(activeTriggerValue))
                            }
                        }
                        .frame(height: 12)
                    }
                    
                    // Individual L2 & R2 Triggers Live Values
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Text("L2:")
                                .font(.subheadline.monospaced().weight(.bold))
                            ProgressView(value: Double(controllerState.triggerL2))
                                .accentColor(.green)
                            Text("\(Int(controllerState.triggerL2 * 100))%")
                                .font(.caption.monospaced().weight(.semibold))
                                .frame(width: 32)
                        }
                        
                        HStack(spacing: 6) {
                            Text("R2:")
                                .font(.subheadline.monospaced().weight(.bold))
                            ProgressView(value: Double(controllerState.triggerR2))
                                .accentColor(.green)
                            Text("\(Int(controllerState.triggerR2 * 100))%")
                                .font(.caption.monospaced().weight(.semibold))
                                .frame(width: 32)
                        }
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                .cornerRadius(10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(manager.isTriggerDynoTestActive ? Color.green.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}
