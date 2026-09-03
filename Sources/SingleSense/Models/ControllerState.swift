import Foundation
import Combine

public final class ControllerState: ObservableObject {
    // Connection & Battery
    @Published public var isConnected: Bool = false
    @Published public var controllerName: String = "PlayStation 5 DualSense"
    @Published public var model: ControllerModel = .dualsense
    @Published public var connectionType: ConnectionType = .unknown
    @Published public var batteryLevel: Float = 1.0 // 0.0 ... 1.0
    @Published public var isBatteryCharging: Bool = false
    
    // Action Buttons
    @Published public var buttonCross: Bool = false
    @Published public var buttonCircle: Bool = false
    @Published public var buttonSquare: Bool = false
    @Published public var buttonTriangle: Bool = false
    
    // D-Pad
    @Published public var dpadUp: Bool = false
    @Published public var dpadDown: Bool = false
    @Published public var dpadLeft: Bool = false
    @Published public var dpadRight: Bool = false
    
    // Bumpers and Triggers
    @Published public var buttonL1: Bool = false
    @Published public var buttonR1: Bool = false
    @Published public var triggerL2: Float = 0.0 // 0.0 ... 1.0
    @Published public var triggerR2: Float = 0.0 // 0.0 ... 1.0
    @Published public var buttonL2: Bool = false
    @Published public var buttonR2: Bool = false
    
    // Thumbsticks
    @Published public var leftStickX: Float = 0.0 // -1.0 ... 1.0
    @Published public var leftStickY: Float = 0.0 // -1.0 ... 1.0
    @Published public var buttonL3: Bool = false
    
    @Published public var rightStickX: Float = 0.0 // -1.0 ... 1.0
    @Published public var rightStickY: Float = 0.0 // -1.0 ... 1.0
    @Published public var buttonR3: Bool = false
    
    // Special Buttons
    @Published public var buttonPS: Bool = false
    @Published public var buttonTouchpad: Bool = false
    @Published public var buttonMute: Bool = false
    @Published public var buttonShare: Bool = false     // Create button
    @Published public var buttonOptions: Bool = false
    
    // Touchpad multi-touch
    @Published public var touch1Active: Bool = false
    @Published public var touch1X: Float = 0.5
    @Published public var touch1Y: Float = 0.5
    @Published public var touch2Active: Bool = false
    @Published public var touch2X: Float = 0.5
    @Published public var touch2Y: Float = 0.5
    
    // Motion IMU (Gyroscope & Accelerometer)
    @Published public var gyroPitch: Float = 0.0  // deg/s or rad/s
    @Published public var gyroRoll: Float = 0.0
    @Published public var gyroYaw: Float = 0.0
    @Published public var accelX: Float = 0.0     // Gs
    @Published public var accelY: Float = 0.0
    @Published public var accelZ: Float = -1.0
    
    // DualSense Edge Specific
    @Published public var isEdge: Bool = false
    @Published public var paddleL4: Bool = false
    @Published public var paddleR4: Bool = false
    @Published public var paddleL5: Bool = false
    @Published public var paddleR5: Bool = false
    @Published public var buttonFnL: Bool = false
    @Published public var buttonFnR: Bool = false
    
    // Live Output Telemetry
    @Published public var currentLightbarColor: RGBColor = RGBColor(red: 0.0, green: 0.4, blue: 1.0)
    @Published public var leftRumbleIntensity: Float = 0.0
    @Published public var rightRumbleIntensity: Float = 0.0
    @Published public var currentFPS: Double = 60.0
    @Published public var packetsSent: UInt64 = 0
    @Published public var linkHealth: LinkHealth = .healthy
    
    public init() {}
    
    public func resetInputs() {
        buttonCross = false
        buttonCircle = false
        buttonSquare = false
        buttonTriangle = false
        dpadUp = false
        dpadDown = false
        dpadLeft = false
        dpadRight = false
        buttonL1 = false
        buttonR1 = false
        triggerL2 = 0.0
        triggerR2 = 0.0
        buttonL2 = false
        buttonR2 = false
        leftStickX = 0.0
        leftStickY = 0.0
        buttonL3 = false
        rightStickX = 0.0
        rightStickY = 0.0
        buttonR3 = false
        buttonPS = false
        buttonTouchpad = false
        buttonMute = false
        buttonShare = false
        buttonOptions = false
        touch1Active = false
        touch2Active = false
        gyroPitch = 0.0
        gyroRoll = 0.0
        gyroYaw = 0.0
        accelX = 0.0
        accelY = 0.0
        accelZ = -1.0
        paddleL4 = false
        paddleR4 = false
        paddleL5 = false
        paddleR5 = false
        buttonFnL = false
        buttonFnR = false
    }
}
