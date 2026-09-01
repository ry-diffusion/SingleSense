import SwiftUI

public struct MotionSensorView: View {
    @ObservedObject var state = DualSenseManager.shared.controllerState
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 3D Artificial Horizon Indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                        )
                    
                    VStack(spacing: 12) {
                        HStack {
                            Label("3D Attitude & Horizon", systemImage: "gyroscope")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text("Tilt the physical controller to see live motion")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        // Artificial Horizon Circle
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.6))
                                .frame(width: 140, height: 140)
                                .overlay(
                                    Circle().stroke(Color.cyan.opacity(0.5), lineWidth: 2)
                                )
                            
                            // Sky & Ground Half-Spheres
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.6), Color.brown.opacity(0.6)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 136, height: 136)
                                .rotationEffect(.degrees(Double(state.gyroRoll) * 45.0))
                                .offset(y: CGFloat(state.gyroPitch) * 20.0)
                                .clipShape(Circle())
                            
                            // Center Crosshair
                            Rectangle().fill(Color.yellow).frame(width: 40, height: 2)
                            Circle().fill(Color.yellow).frame(width: 6, height: 6)
                        }
                        .frame(height: 150)
                    }
                    .padding(16)
                }
                
                // 6-Axis IMU Sensor Gauges
                HStack(alignment: .top, spacing: 16) {
                    // Gyroscope Card
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Gyroscope (Angular Velocity)", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .bold))
                        
                        sensorRow(label: "Pitch (X)", value: state.gyroPitch, unit: "\u{00B0}/s", color: .red)
                        sensorRow(label: "Roll (Y)", value: state.gyroRoll, unit: "\u{00B0}/s", color: .green)
                        sensorRow(label: "Yaw (Z)", value: state.gyroYaw, unit: "\u{00B0}/s", color: .blue)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(12)
                    
                    // Accelerometer Card
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Accelerometer (G-Force)", systemImage: "move.3d")
                            .font(.system(size: 13, weight: .bold))
                        
                        sensorRow(label: "Accel X", value: state.accelX, unit: "G", color: .orange)
                        sensorRow(label: "Accel Y", value: state.accelY, unit: "G", color: .purple)
                        sensorRow(label: "Accel Z", value: state.accelZ, unit: "G", color: .cyan)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(12)
                }
            }
            .padding(20)
        }
    }
    
    private func sensorRow(label: String, value: Float, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(String(format: "%+.2f %@", value, unit))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }
            
            // Value Level Bar
            GeometryReader { geo in
                ZStack(alignment: .center) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 6)
                    
                    let clamped = max(-1.0, min(1.0, value))
                    let width = abs(CGFloat(clamped)) * (geo.size.width / 2.0)
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: width, height: 6)
                        .offset(x: clamped >= 0 ? width / 2.0 : -width / 2.0)
                }
            }
            .frame(height: 6)
        }
    }
}
