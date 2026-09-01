import Foundation

public struct ControllerProfile: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var description: String
    public var iconName: String
    public var lightbar: LightbarConfiguration
    public var leftTrigger: SingleTriggerConfig
    public var rightTrigger: SingleTriggerConfig
    public var triggersLinked: Bool
    public var leftRumble: Float
    public var rightRumble: Float
    public var createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        iconName: String = "gamecontroller.fill",
        lightbar: LightbarConfiguration = LightbarConfiguration(),
        leftTrigger: SingleTriggerConfig = SingleTriggerConfig(),
        rightTrigger: SingleTriggerConfig = SingleTriggerConfig(),
        triggersLinked: Bool = false,
        leftRumble: Float = 0.0,
        rightRumble: Float = 0.0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
        self.lightbar = lightbar
        self.leftTrigger = leftTrigger
        self.rightTrigger = rightTrigger
        self.triggersLinked = triggersLinked
        self.leftRumble = leftRumble
        self.rightRumble = rightRumble
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct DefaultProfiles {
    public static func createDefaults() -> [ControllerProfile] {
        var classicProfile = ControllerProfile(
            name: "PlayStation Classic",
            description: "Standard PlayStation Blue lighting with responsive default triggers.",
            iconName: "playstation.logo"
        )
        classicProfile.lightbar.mode = .staticColor
        classicProfile.lightbar.staticColor = RGBColor(red: 0.0, green: 0.38, blue: 1.0)
        
        var rainbowProfile = ControllerProfile(
            name: "Rainbow Euphoria",
            description: "Smooth 60 FPS RGB rainbow lighting with responsive standard triggers.",
            iconName: "rainbow"
        )
        rainbowProfile.lightbar.mode = .rainbow
        rainbowProfile.lightbar.rainbowSpeed = 1.0
        
        var fpsProfile = ControllerProfile(
            name: "FPS Shooter Pro",
            description: "Heavy Desert Eagle trigger break on R2, feedback on L2, Cyberpunk Cyan lighting.",
            iconName: "scope"
        )
        fpsProfile.lightbar.mode = .staticColor
        fpsProfile.lightbar.staticColor = RGBColor(red: 0.0, green: 0.95, blue: 0.95)
        fpsProfile.leftTrigger.mode = .feedback
        fpsProfile.leftTrigger.startPosition = 0.3
        fpsProfile.leftTrigger.strength = 0.5
        fpsProfile.rightTrigger.mode = .weapon
        fpsProfile.rightTrigger.startPosition = 0.25
        fpsProfile.rightTrigger.endPosition = 0.85
        fpsProfile.rightTrigger.strength = 0.95
        
        var racingProfile = ControllerProfile(
            name: "Racing Simulator",
            description: "ABS braking pulsation on L2 and accelerator progressive resistance on R2.",
            iconName: "car.fill"
        )
        racingProfile.lightbar.mode = .breathing
        racingProfile.lightbar.staticColor = RGBColor(red: 1.0, green: 0.08, blue: 0.1)
        racingProfile.leftTrigger.mode = .vibration
        racingProfile.leftTrigger.startPosition = 0.5
        racingProfile.leftTrigger.frequency = 28.0
        racingProfile.leftTrigger.amplitude = 0.9
        racingProfile.rightTrigger.mode = .slopeFeedback
        racingProfile.rightTrigger.startPosition = 0.0
        racingProfile.rightTrigger.endPosition = 1.0
        racingProfile.rightTrigger.startStrength = 0.1
        racingProfile.rightTrigger.endStrength = 0.8
        
        var batterySaver = ControllerProfile(
            name: "Battery Saver",
            description: "Low-power dim breathing indicator with adaptive triggers disabled.",
            iconName: "battery.100.bolt"
        )
        batterySaver.lightbar.mode = .batteryReactive
        batterySaver.leftTrigger.mode = .off
        batterySaver.rightTrigger.mode = .off
        
        var cyberpunkProfile = ControllerProfile(
            name: "Night City 2077",
            description: "High-energy Cyberpunk strobe lighting with clicky mechanical trigger switches.",
            iconName: "bolt.fill"
        )
        cyberpunkProfile.lightbar.mode = .strobe
        cyberpunkProfile.leftTrigger.mode = .weapon
        cyberpunkProfile.leftTrigger.startPosition = 0.1
        cyberpunkProfile.leftTrigger.endPosition = 0.3
        cyberpunkProfile.leftTrigger.strength = 0.8
        cyberpunkProfile.rightTrigger.mode = .weapon
        cyberpunkProfile.rightTrigger.startPosition = 0.1
        cyberpunkProfile.rightTrigger.endPosition = 0.3
        cyberpunkProfile.rightTrigger.strength = 0.8
        
        return [classicProfile, fpsProfile, rainbowProfile, racingProfile, batterySaver, cyberpunkProfile]
    }
}
