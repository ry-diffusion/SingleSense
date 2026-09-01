import Foundation

public enum ConnectionType: String, Codable, CaseIterable {
    case usb = "USB"
    case bluetooth = "Bluetooth"
    case unknown = "Unknown"
    
    public var iconName: String {
        switch self {
        case .usb:
            return "cable.connector"
        case .bluetooth:
            return "wave.3.right"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

public enum ControllerModel: String, Codable, CaseIterable {
    case dualsense = "DualSense Wireless Controller"
    case dualsenseEdge = "DualSense Edge Wireless Controller"
    
    public var shortName: String {
        switch self {
        case .dualsense: return "DualSense"
        case .dualsenseEdge: return "DualSense Edge"
        }
    }
}

public enum LightingMode: String, Codable, CaseIterable, Identifiable {
    case staticColor = "Static Color"
    case rainbow = "60 FPS Rainbow"
    case breathing = "Breathing Pulse"
    case batteryReactive = "Battery Gauge"
    case triggerReactive = "Trigger Reactive"
    case strobe = "Cyberpunk Strobe"
    case musicSync = "Music Sync"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .staticColor: return "paintpalette.fill"
        case .rainbow: return "rainbow"
        case .breathing: return "lungs.fill"
        case .batteryReactive: return "battery.100.bolt"
        case .triggerReactive: return "hand.tap.fill"
        case .strobe: return "bolt.fill"
        case .musicSync: return "waveform"
        }
    }
    
    public var description: String {
        switch self {
        case .staticColor:
            return "Set a solid, customized RGB color on the lightbar."
        case .rainbow:
            return "Ultra-smooth 60 FPS HSV color cycle inspired by dualsense-rainbow."
        case .breathing:
            return "Gently pulses the lightbar with a smooth sine wave fade."
        case .batteryReactive:
            return "Dynamic color indicator: Green (High) -> Yellow (Mid) -> Red (Low)."
        case .triggerReactive:
            return "Lightbar shifts color and brightness based on trigger pressure."
        case .strobe:
            return "High-energy Cyberpunk strobe lighting effect."
        case .musicSync:
            return "Reacts to whatever the Mac is playing, in real time."
        }
    }
}

public enum TriggerModeType: String, Codable, CaseIterable, Identifiable {
    case off = "Off / Standard"
    case feedback = "Rigid Feedback"
    case weapon = "Weapon Pull"
    case vibration = "Vibration"
    case slopeFeedback = "Slope Feedback"
    case machineGun = "Machine Gun"
    case customCurve = "10-Zone Curve"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .off: return "circle.slash"
        case .feedback: return "lock.fill"
        case .weapon: return "scope"
        case .vibration: return "waveform.path"
        case .slopeFeedback: return "chart.line.uptrend.xyaxis"
        case .machineGun: return "burst.fill"
        case .customCurve: return "slider.vertical.3"
        }
    }
}

public enum PlayerLEDMode: String, Codable, CaseIterable, Identifiable {
    case off = "Off"
    case player1 = "Player 1 (Center)"
    case player2 = "Player 2 (Inner Two)"
    case player3 = "Player 3 (Three LEDs)"
    case player4 = "Player 4 (Outer Four)"
    case player5 = "Player 5 (All Five)"
    
    public var id: String { rawValue }
    
    public var bitmask: UInt8 {
        switch self {
        case .off: return 0x00
        case .player1: return 0x04      // 00100 (center)
        case .player2: return 0x0A      // 01010 (inner 2)
        case .player3: return 0x15      // 10101 (3 leds)
        case .player4: return 0x1B      // 11011 (outer 4)
        case .player5: return 0x1F      // 11111 (all 5)
        }
    }
}

public enum PlayerLEDBrightness: String, Codable, CaseIterable, Identifiable {
    case off = "Off"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    
    public var id: String { rawValue }
    
    /// The firmware only defines three levels. "Off" is expressed by clearing
    /// the player LED mask, not by an out-of-range brightness byte.
    public var rawValueByte: UInt8 {
        switch self {
        case .high: return 0x00
        case .medium: return 0x01
        case .low, .off: return 0x02
        }
    }

    /// True when the indicator row should be dark regardless of the pattern.
    public var extinguishesLEDs: Bool { self == .off }
}

public enum MicLEDMode: String, Codable, CaseIterable, Identifiable {
    case off = "Off"
    case on = "Solid Orange"
    case pulse = "Pulse"
    
    public var id: String { rawValue }
    
    public var rawValueByte: UInt8 {
        switch self {
        case .off: return 0x00
        case .on: return 0x01
        case .pulse: return 0x02
        }
    }
}

/// How the lightbar maps the analysed audio spectrum onto colour.
public enum MusicSyncStyle: String, Codable, CaseIterable, Identifiable {
    /// Red follows bass, green mid, blue treble — the spectrum drawn directly.
    case spectrum = "Spectrum"
    /// Chosen colour, brightness driven by loudness.
    case pulse = "Colour Pulse"
    /// Hue swept by where the energy sits, brightness by loudness.
    case hueShift = "Hue Sweep"
    /// Flashes the chosen colour on each detected beat.
    case beatFlash = "Beat Flash"

    public var id: String { rawValue }

    public var detail: String {
        switch self {
        case .spectrum: return "R/G/B track the bass, mid and treble bands."
        case .pulse: return "Your colour, breathing with the track's loudness."
        case .hueShift: return "Bass-heavy runs warm, bright mixes run cool."
        case .beatFlash: return "Dark between beats, full colour on each hit."
        }
    }
}

/// What the five-lamp player indicator row does while Music Sync is driving
/// the lightbar.
public enum PlayerLEDAudioStyle: String, Codable, CaseIterable, Identifiable {
    /// Leave the row on the pattern chosen in the Player Indicator section.
    case fixed = "Fixed Pattern"
    /// Fills left to right with the overall level.
    case vuMeter = "VU Meter"
    /// Grows outward from the middle lamp, reusing the console's own
    /// centred player patterns as the progression.
    case centerSpread = "Center Spread"
    /// All five lamps flash on each detected beat.
    case beatPulse = "Beat Pulse"

    public var id: String { rawValue }

    public var detail: String {
        switch self {
        case .fixed: return "Row stays on your chosen player pattern."
        case .vuMeter: return "Lamps fill left to right with loudness."
        case .centerSpread: return "Grows outward from the centre lamp."
        case .beatPulse: return "All five snap on with every beat."
        }
    }
}

/// Helpers for the five-lamp player indicator row.
public enum PlayerLEDIndicator {
    public static let lampCount = 5

    /// The console's centred progression, indexed by how many lamps are lit.
    /// Index 0 is dark; the rest match `player_ids[]` in the kernel driver.
    public static let centredPatterns: [UInt8] = [0x00, 0x04, 0x0A, 0x15, 0x1B, 0x1F]

    /// A bar filling from the leftmost lamp.
    public static func bar(lampsLit: Int) -> UInt8 {
        let count = min(max(lampsLit, 0), lampCount)
        guard count > 0 else { return 0 }
        return UInt8((1 << count) - 1)
    }

    /// Lamps to light for a `0...1` level, rounding so that any audible
    /// signal lights at least one lamp.
    public static func lamps(for level: Float) -> Int {
        guard level.isFinite, level > 0.02 else { return 0 }
        let scaled = (level * Float(lampCount)).rounded(.up)
        return min(max(Int(scaled), 1), lampCount)
    }
}

/// How the rumble motors follow the audio while Music Sync is active.
///
/// The two motors are not interchangeable: the left one is a heavy
/// low-frequency weight, the right a lighter, faster one. Mapping bass to the
/// left and the upper bands to the right is what makes the effect read as the
/// music rather than as undifferentiated buzzing.
public enum MusicHapticsStyle: String, Codable, CaseIterable, Identifiable {
    case off = "Off"
    /// Heavy motor only, following the bass band.
    case bassKick = "Bass Kick"
    /// Heavy motor on bass, light motor on mids and treble.
    case fullRange = "Full Range"
    /// A short thump on the heavy motor for each detected beat.
    case beatPunch = "Beat Punch"

    public var id: String { rawValue }

    public var detail: String {
        switch self {
        case .off: return "Motors stay idle."
        case .bassKick: return "Heavy motor rides the bass line."
        case .fullRange: return "Bass on the left motor, highs on the right."
        case .beatPunch: return "One short thump per beat."
        }
    }
}

/// Shaping for a rumble motor driven by a normalised signal.
public enum RumbleCurve {
    /// Below this the signal is treated as silence.
    public static let gate: Float = 0.06
    /// The motors barely move under this, so an audible signal starts here
    /// instead of ramping up from a stall.
    public static let floor: Float = 0.18

    public static func shape(_ signal: Float) -> Float {
        guard signal.isFinite, signal > gate else { return 0 }
        let normalised = min((signal - gate) / (1 - gate), 1)
        return floor + normalised * (1 - floor)
    }
}
