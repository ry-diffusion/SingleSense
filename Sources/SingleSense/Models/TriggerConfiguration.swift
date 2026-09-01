import Foundation

public struct SingleTriggerConfig: Codable, Equatable {
    public var mode: TriggerModeType = .off
    public var startPosition: Float = 0.0          // 0.0 ... 1.0
    public var endPosition: Float = 1.0            // 0.0 ... 1.0
    public var strength: Float = 0.7               // 0.0 ... 1.0
    public var startStrength: Float = 0.2          // 0.0 ... 1.0 (Slope)
    public var endStrength: Float = 0.8            // 0.0 ... 1.0 (Slope)
    public var frequency: Float = 25.0             // 1 ... 255 Hz
    public var amplitude: Float = 0.7              // 0.0 ... 1.0 (Vibration)
    public var custom10Zones: [Float] = [0.0, 0.1, 0.2, 0.3, 0.5, 0.7, 0.8, 0.9, 1.0, 1.0]
    public var custom10Vibrations: [Float] = [0.0, 0.0, 0.0, 0.3, 0.5, 0.8, 1.0, 0.8, 0.5, 0.2]
    
    public init(mode: TriggerModeType = .off) {
        self.mode = mode
    }
}

public struct TriggerPreset: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let iconName: String
    public let leftConfig: SingleTriggerConfig
    public let rightConfig: SingleTriggerConfig
    
    public init(id: String, name: String, description: String, iconName: String, leftConfig: SingleTriggerConfig, rightConfig: SingleTriggerConfig) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
        self.leftConfig = leftConfig
        self.rightConfig = rightConfig
    }
}

public struct TriggerPresets {
    public static let all: [TriggerPreset] = [
        TriggerPreset(
            id: "default_off",
            name: "Default (Standard)",
            description: "No adaptive resistance. Standard controller feel.",
            iconName: "circle.slash",
            leftConfig: SingleTriggerConfig(mode: .off),
            rightConfig: SingleTriggerConfig(mode: .off)
        ),
        TriggerPreset(
            id: "desert_eagle",
            name: "Heavy Handgun / Desert Eagle",
            description: "Short pre-travel, solid resistance wall, and crisp break.",
            iconName: "scope",
            leftConfig: {
                var c = SingleTriggerConfig(mode: .feedback)
                c.startPosition = 0.3
                c.strength = 0.5
                return c
            }(),
            rightConfig: {
                var c = SingleTriggerConfig(mode: .weapon)
                c.startPosition = 0.25
                c.endPosition = 0.85
                c.strength = 0.95
                return c
            }()
        ),
        TriggerPreset(
            id: "sniper_rifle",
            name: "Sniper Rifle (Heavy Wall)",
            description: "Deep trigger pull with an intense break threshold.",
            iconName: "cross.fill",
            leftConfig: {
                var c = SingleTriggerConfig(mode: .feedback)
                c.startPosition = 0.4
                c.strength = 0.6
                return c
            }(),
            rightConfig: {
                var c = SingleTriggerConfig(mode: .weapon)
                c.startPosition = 0.45
                c.endPosition = 0.90
                c.strength = 1.0
                return c
            }()
        ),
        TriggerPreset(
            id: "shotgun",
            name: "Pump Action Shotgun",
            description: "Heavy initial cocking resistance followed by rapid release.",
            iconName: "burst.fill",
            leftConfig: {
                var c = SingleTriggerConfig(mode: .feedback)
                c.startPosition = 0.2
                c.strength = 0.4
                return c
            }(),
            rightConfig: {
                var c = SingleTriggerConfig(mode: .slopeFeedback)
                c.startPosition = 0.1
                c.endPosition = 0.7
                c.startStrength = 0.3
                c.endStrength = 1.0
                return c
            }()
        ),
        TriggerPreset(
            id: "assault_burst",
            name: "Assault Rifle Burst",
            description: "Vibrating automatic rapid-fire pulse upon trigger pull.",
            iconName: "waveform.path",
            leftConfig: {
                var c = SingleTriggerConfig(mode: .feedback)
                c.startPosition = 0.2
                c.strength = 0.3
                return c
            }(),
            rightConfig: {
                var c = SingleTriggerConfig(mode: .vibration)
                c.startPosition = 0.15
                c.frequency = 40.0
                c.amplitude = 0.85
                return c
            }()
        ),
        TriggerPreset(
            id: "compound_bow",
            name: "Compound Bow & Arrow",
            description: "Gradual elastic tension buildup that eases right at full draw.",
            iconName: "arrow.up.right.circle.fill",
            leftConfig: {
                var c = SingleTriggerConfig(mode: .slopeFeedback)
                c.startPosition = 0.0
                c.endPosition = 0.8
                c.startStrength = 0.1
                c.endStrength = 0.9
                return c
            }(),
            rightConfig: {
                var c = SingleTriggerConfig(mode: .customCurve)
                c.custom10Zones = [0.1, 0.2, 0.4, 0.6, 0.85, 1.0, 0.95, 0.7, 0.5, 0.4]
                return c
            }()
        ),
        TriggerPreset(
            id: "abs_brakes",
            name: "Racing ABS Brake Pedal",
            description: "Simulates anti-lock braking pulsation when braking hard.",
            iconName: "car.fill",
            leftConfig: {
                var c = SingleTriggerConfig(mode: .vibration)
                c.startPosition = 0.5
                c.frequency = 28.0
                c.amplitude = 0.9
                return c
            }(),
            rightConfig: {
                var c = SingleTriggerConfig(mode: .slopeFeedback)
                c.startPosition = 0.0
                c.endPosition = 1.0
                c.startStrength = 0.1
                c.endStrength = 0.8
                return c
            }()
        ),
        TriggerPreset(
            id: "clicky_switch",
            name: "Mechanical Click Switch",
            description: "Simulates a crisp tactile click like a mechanical mouse switch.",
            iconName: "computermouse.fill",
            leftConfig: {
                var c = SingleTriggerConfig(mode: .weapon)
                c.startPosition = 0.1
                c.endPosition = 0.3
                c.strength = 0.8
                return c
            }(),
            rightConfig: {
                var c = SingleTriggerConfig(mode: .weapon)
                c.startPosition = 0.1
                c.endPosition = 0.3
                c.strength = 0.8
                return c
            }()
        )
    ]
}

// MARK: - Validation

extension SingleTriggerConfig {
    /// Frequency the machine-gun preset cycles at, in Hz.
    static let machineGunFrequency: Float = 45
    /// Duty-cycle tuning for the machine-gun effect.
    static let machineGunPeriod: UInt8 = 3

    /// Clamps every field into the range the wire format accepts.
    ///
    /// Configurations reach this type from persisted JSON, so nothing here can
    /// be assumed to be in range — and `UInt8(float)` traps rather than
    /// saturating when it is not.
    public func sanitized() -> SingleTriggerConfig {
        var copy = self
        copy.startPosition = DSScale.clamp01(startPosition)
        copy.endPosition = DSScale.clamp01(endPosition)
        copy.strength = DSScale.clamp01(strength)
        copy.startStrength = DSScale.clamp01(startStrength)
        copy.endStrength = DSScale.clamp01(endStrength)
        copy.amplitude = DSScale.clamp01(amplitude)
        copy.frequency = frequency.isFinite ? min(max(frequency, 1), 255) : 1

        copy.custom10Zones = Self.normalizedZones(custom10Zones)
        copy.custom10Vibrations = Self.normalizedZones(custom10Vibrations)
        return copy
    }

    private static func normalizedZones(_ zones: [Float]) -> [Float] {
        var result = zones.prefix(DSTriggerEffect.zoneCount).map { DSScale.clamp01($0) }
        while result.count < DSTriggerEffect.zoneCount { result.append(0) }
        return result
    }

    // Decoding runs the same clamps, so a hand-edited profiles.json cannot
    // produce values that trap later on the HID send path.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var config = SingleTriggerConfig()
        config.mode = try container.decodeIfPresent(TriggerModeType.self, forKey: .mode) ?? .off
        config.startPosition = try container.decodeIfPresent(Float.self, forKey: .startPosition) ?? 0
        config.endPosition = try container.decodeIfPresent(Float.self, forKey: .endPosition) ?? 1
        config.strength = try container.decodeIfPresent(Float.self, forKey: .strength) ?? 0.7
        config.startStrength = try container.decodeIfPresent(Float.self, forKey: .startStrength) ?? 0.2
        config.endStrength = try container.decodeIfPresent(Float.self, forKey: .endStrength) ?? 0.8
        config.frequency = try container.decodeIfPresent(Float.self, forKey: .frequency) ?? 25
        config.amplitude = try container.decodeIfPresent(Float.self, forKey: .amplitude) ?? 0.7
        if let zones = try container.decodeIfPresent([Float].self, forKey: .custom10Zones) {
            config.custom10Zones = zones
        }
        if let vibrations = try container.decodeIfPresent([Float].self, forKey: .custom10Vibrations) {
            config.custom10Vibrations = vibrations
        }
        self = config.sanitized()
    }
}

// MARK: - Wire encoding

extension SingleTriggerConfig {
    /// Writes this configuration as an 11-byte adaptive trigger effect block.
    public func encode(into report: inout [UInt8], at offset: Int) {
        let config = sanitized()

        switch config.mode {
        case .off:
            DSTriggerEffect.off(into: &report, at: offset)

        case .feedback:
            // Uniform resistance from the start zone through the end of travel.
            let level = DSScale.level(config.strength)
            let start = DSScale.zone(config.startPosition)
            var levels = [UInt8](repeating: 0, count: DSTriggerEffect.zoneCount)
            for zone in start..<DSTriggerEffect.zoneCount { levels[zone] = level }
            DSTriggerEffect.feedback(levels: levels, into: &report, at: offset)

        case .weapon:
            DSTriggerEffect.weapon(
                startZone: DSScale.zone(config.startPosition),
                endZone: DSScale.zone(config.endPosition),
                level: DSScale.level(config.strength),
                into: &report,
                at: offset
            )

        case .vibration:
            let amplitude = DSScale.level(config.amplitude)
            let start = DSScale.zone(config.startPosition)
            var amplitudes = [UInt8](repeating: 0, count: DSTriggerEffect.zoneCount)
            for zone in start..<DSTriggerEffect.zoneCount { amplitudes[zone] = amplitude }
            DSTriggerEffect.vibration(
                amplitudes: amplitudes,
                frequency: DSScale.rawByte(config.frequency),
                into: &report,
                at: offset
            )

        case .slopeFeedback:
            DSTriggerEffect.feedback(
                levels: config.slopeLevels(),
                into: &report,
                at: offset
            )

        case .machineGun:
            let level = DSScale.level(config.strength)
            // Machine amplitudes are 3-bit (0...7), one notch narrower than
            // the 0...8 force levels used by the other effects.
            let amplitude = UInt8(min(Int(level), 7))
            DSTriggerEffect.machine(
                startZone: DSScale.zone(config.startPosition),
                endZone: DSTriggerEffect.zoneCount - 1,
                amplitudeA: amplitude,
                amplitudeB: amplitude,
                frequency: DSScale.rawByte(Self.machineGunFrequency),
                period: Self.machineGunPeriod,
                into: &report,
                at: offset
            )

        case .customCurve:
            DSTriggerEffect.feedback(
                levels: config.custom10Zones.map { DSScale.level($0) },
                into: &report,
                at: offset
            )
        }
    }

    /// Linear force ramp from `startStrength` at `startPosition` to
    /// `endStrength` at `endPosition`, held at `endStrength` afterwards.
    func slopeLevels() -> [UInt8] {
        let count = DSTriggerEffect.zoneCount
        let start = min(DSScale.zone(startPosition), count - 2)
        let end = min(max(DSScale.zone(endPosition), start + 1), count - 1)

        // The effect needs a non-zero level wherever it is active, so both
        // endpoints are lifted into 1...8 the way the reference encoder does.
        let startLevel = Int(max(DSScale.level(startStrength), 1))
        let endLevel = Int(max(DSScale.level(endStrength), 1))
        let slope = Float(endLevel - startLevel) / Float(end - start)

        var levels = [UInt8](repeating: 0, count: count)
        for zone in start..<count {
            let value = zone <= end
                ? Int((Float(startLevel) + slope * Float(zone - start)).rounded())
                : endLevel
            levels[zone] = UInt8(min(max(value, 1), Int(DSTriggerEffect.maxLevel)))
        }
        return levels
    }
}
