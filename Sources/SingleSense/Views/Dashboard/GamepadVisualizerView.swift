import SwiftUI

public struct GamepadVisualizerView: View {
    @ObservedObject var state: ControllerState
    
    public init(state: ControllerState) {
        self.state = state
    }
    
    public var body: some View {
        ZStack {
            // Background Container
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(state.currentLightbarColor.color.opacity(0.3), lineWidth: 1.5)
                )
                .shadow(color: state.currentLightbarColor.color.opacity(0.15), radius: 16)
            
            VStack(spacing: 12) {
                // Top Trigger & Bumper Bar
                HStack {
                    // Left Trigger & Bumper
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("L2")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(state.buttonL2 ? .blue : .secondary)
                            
                            // L2 Gauge
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.secondary.opacity(0.2))
                                    Capsule()
                                        .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: geo.size.width * CGFloat(state.triggerL2))
                                }
                            }
                            .frame(width: 80, height: 8)
                            
                            Text("\(Int(state.triggerL2 * 100))%")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }
                        
                        // L1 Button
                        Text("L1")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(state.buttonL1 ? Color.blue : Color.secondary.opacity(0.2))
                            .foregroundColor(state.buttonL1 ? .white : .primary)
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    // Center Lightbar Glow Bar
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(state.currentLightbarColor.color)
                            .frame(width: 140, height: 6)
                            .shadow(color: state.currentLightbarColor.color.opacity(0.8), radius: 8)
                        
                        Text("LIGHTBAR")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(state.currentLightbarColor.color)
                    }
                    
                    Spacer()
                    
                    // Right Trigger & Bumper
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("\(Int(state.triggerR2 * 100))%")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 32, alignment: .leading)
                            
                            // R2 Gauge
                            GeometryReader { geo in
                                ZStack(alignment: .trailing) {
                                    Capsule().fill(Color.secondary.opacity(0.2))
                                    Capsule()
                                        .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: geo.size.width * CGFloat(state.triggerR2))
                                }
                            }
                            .frame(width: 80, height: 8)
                            
                            Text("R2")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(state.buttonR2 ? .blue : .secondary)
                        }
                        
                        // R1 Button
                        Text("R1")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(state.buttonR1 ? Color.blue : Color.secondary.opacity(0.2))
                            .foregroundColor(state.buttonR1 ? .white : .primary)
                            .cornerRadius(4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                
                // Main Controller Surface
                HStack(alignment: .center, spacing: 20) {
                    // Left Section: D-Pad & Left Stick
                    VStack(spacing: 16) {
                        // D-Pad Cross
                        ZStack {
                            Circle()
                                .fill(Color.secondary.opacity(0.1))
                                .frame(width: 80, height: 80)
                            
                            // Up
                            dpadButton(symbol: "chevron.up", isActive: state.dpadUp)
                                .offset(y: -24)
                            // Down
                            dpadButton(symbol: "chevron.down", isActive: state.dpadDown)
                                .offset(y: 24)
                            // Left
                            dpadButton(symbol: "chevron.left", isActive: state.dpadLeft)
                                .offset(x: -24)
                            // Right
                            dpadButton(symbol: "chevron.right", isActive: state.dpadRight)
                                .offset(x: 24)
                        }
                        
                        // Left Thumbstick (L3)
                        stickVisualizer(
                            name: "L3",
                            x: state.leftStickX,
                            y: state.leftStickY,
                            isPressed: state.buttonL3
                        )
                    }
                    
                    Spacer()
                    
                    // Center Section: Touchpad & PS / Create / Options / Mic Buttons
                    VStack(spacing: 10) {
                        // Touchpad Surface
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(state.buttonTouchpad ? Color.blue.opacity(0.3) : Color.secondary.opacity(0.15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(state.buttonTouchpad ? Color.blue : Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                                .frame(width: 140, height: 75)
                            
                            if state.touch1Active {
                                Circle()
                                    .fill(Color.cyan)
                                    .frame(width: 14, height: 14)
                                    .shadow(color: Color.cyan, radius: 4)
                                    .position(
                                        x: CGFloat(state.touch1X) * 140,
                                        y: CGFloat(state.touch1Y) * 75
                                    )
                            }
                            
                            Text("TOUCHPAD")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        .frame(width: 140, height: 75)
                        
                        // Middle Buttons (Share, PS, Options)
                        HStack(spacing: 16) {
                            // Create / Share Button
                            buttonIndicator(label: "SHARE", isActive: state.buttonShare)
                            
                            // PS Home Button
                            ZStack {
                                Circle()
                                    .fill(state.buttonPS ? Color.blue : Color.secondary.opacity(0.2))
                                    .frame(width: 26, height: 26)
                                Image(systemName: "playstation.logo")
                                    .font(.system(size: 14))
                                    .foregroundColor(state.buttonPS ? .white : .primary)
                            }
                            
                            // Options Button
                            buttonIndicator(label: "OPTIONS", isActive: state.buttonOptions)
                        }
                        
                        // Mic Button
                        HStack(spacing: 4) {
                            Circle()
                                .fill(state.buttonMute ? Color.orange : Color.secondary.opacity(0.3))
                                .frame(width: 6, height: 6)
                            Text("MIC")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(state.buttonMute ? .orange : .secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    // Right Section: Action Buttons & Right Stick
                    VStack(spacing: 16) {
                        // Action Buttons Cluster
                        ZStack {
                            Circle()
                                .fill(Color.secondary.opacity(0.1))
                                .frame(width: 80, height: 80)
                            
                            // Triangle (Top)
                            actionButton(label: "▲", color: .green, isActive: state.buttonTriangle)
                                .offset(y: -24)
                            // Cross (Bottom)
                            actionButton(label: "✖", color: .blue, isActive: state.buttonCross)
                                .offset(y: 24)
                            // Square (Left)
                            actionButton(label: "■", color: .pink, isActive: state.buttonSquare)
                                .offset(x: -24)
                            // Circle (Right)
                            actionButton(label: "●", color: .red, isActive: state.buttonCircle)
                                .offset(x: 24)
                        }
                        
                        // Right Thumbstick (R3)
                        stickVisualizer(
                            name: "R3",
                            x: state.rightStickX,
                            y: state.rightStickY,
                            isPressed: state.buttonR3
                        )
                    }
                }
                .padding(.horizontal, 24)
                
                // Edge Paddles (if DualSense Edge)
                if state.isEdge {
                    HStack(spacing: 24) {
                        Text("L4: \(state.paddleL4 ? "ON" : "OFF")")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(state.paddleL4 ? .blue : .secondary)
                        Text("L5: \(state.paddleL5 ? "ON" : "OFF")")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(state.paddleL5 ? .blue : .secondary)
                        Spacer()
                        Text("EDGE PADDLES")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("R5: \(state.paddleR5 ? "ON" : "OFF")")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(state.paddleR5 ? .blue : .secondary)
                        Text("R4: \(state.paddleR4 ? "ON" : "OFF")")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(state.paddleR4 ? .blue : .secondary)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 8)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(height: 250)
    }
    
    // MARK: - Subviews
    private func dpadButton(symbol: String, isActive: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color.blue : Color.secondary.opacity(0.2))
                .frame(width: 22, height: 22)
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isActive ? .white : .primary)
        }
    }
    
    private func actionButton(label: String, color: Color, isActive: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isActive ? color : Color.secondary.opacity(0.2))
                .frame(width: 22, height: 22)
                .shadow(color: isActive ? color.opacity(0.8) : Color.clear, radius: 4)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isActive ? .white : color)
        }
    }
    
    private func buttonIndicator(label: String, isActive: Bool) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isActive ? Color.blue : Color.secondary.opacity(0.15))
            .foregroundColor(isActive ? .white : .secondary)
            .cornerRadius(4)
    }
    
    private func stickVisualizer(name: String, x: Float, y: Float, isPressed: Bool) -> some View {
        ZStack {
            // Stick Base Boundary
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
                .background(Circle().fill(Color.secondary.opacity(0.08)))
                .frame(width: 54, height: 54)
            
            // Crosshairs
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1, height: 40)
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 40, height: 1)
            
            // Stick Thumb Pad
            Circle()
                .fill(isPressed ? Color.blue : Color.secondary.opacity(0.4))
                .frame(width: 24, height: 24)
                .overlay(
                    Text(name)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(isPressed ? .white : .primary)
                )
                .offset(
                    x: CGFloat(x * 15.0),
                    y: CGFloat(-y * 15.0)
                )
                .shadow(radius: 2)
        }
    }
}
