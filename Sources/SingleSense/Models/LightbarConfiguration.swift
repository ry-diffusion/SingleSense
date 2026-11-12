import Foundation
import SwiftUI

public struct RGBColor: Codable, Equatable {
    public var red: Double      // 0.0 ... 1.0
    public var green: Double    // 0.0 ... 1.0
    public var blue: Double     // 0.0 ... 1.0
    
    public init(red: Double, green: Double, blue: Double) {
        // NaN has to be filtered explicitly: it compares false against every
        // bound, so a plain min/max clamp would let it through.
        self.red = red.isFinite ? max(0.0, min(1.0, red)) : 0.0
        self.green = green.isFinite ? max(0.0, min(1.0, green)) : 0.0
        self.blue = blue.isFinite ? max(0.0, min(1.0, blue)) : 0.0
    }
    
    public var redByte: UInt8 { DSScale.byte(red) }
    public var greenByte: UInt8 { DSScale.byte(green) }
    public var blueByte: UInt8 { DSScale.byte(blue) }

    // The memberwise initialiser clamps, but the synthesised Codable one would
    // not — and a persisted profile is exactly where an out-of-range component
    // comes from.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            red: try container.decodeIfPresent(Double.self, forKey: .red) ?? 0,
            green: try container.decodeIfPresent(Double.self, forKey: .green) ?? 0,
            blue: try container.decodeIfPresent(Double.self, forKey: .blue) ?? 0
        )
    }
    
    public var color: Color {
        Color(red: red, green: green, blue: blue)
    }
    
    public var hexString: String {
        String(format: "#%02X%02X%02X", redByte, greenByte, blueByte)
    }
    
    public static func fromHex(_ hex: String) -> RGBColor {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.hasPrefix("#") {
            clean.remove(at: clean.startIndex)
        }
        guard clean.count == 6, let rgbValue = UInt64(clean, radix: 16) else {
            return RGBColor(red: 0.0, green: 0.4, blue: 1.0)
        }
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        return RGBColor(red: r, green: g, blue: b)
    }
    
    public static func fromHSV(hue: Double, saturation: Double, value: Double) -> RGBColor {
        let h = hue.truncatingRemainder(dividingBy: 1.0) * 6.0
        let s = max(0.0, min(1.0, saturation))
        let v = max(0.0, min(1.0, value))
        
        let c = v * s
        let x = c * (1.0 - abs(h.truncatingRemainder(dividingBy: 2.0) - 1.0))
        let m = v - c
        
        var (r, g, b) = (0.0, 0.0, 0.0)
        switch Int(h) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        
        return RGBColor(red: r + m, green: g + m, blue: b + m)
    }
}

public struct ColorPalettePreset: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let color: RGBColor
}

public struct ColorPresets {
    public static let list: [ColorPalettePreset] = [
        ColorPalettePreset(id: "ps_blue", name: "PlayStation Classic Blue", color: RGBColor(red: 0.0, green: 0.38, blue: 1.0)),
        ColorPalettePreset(id: "cyber_cyan", name: "Cyberpunk Cyan", color: RGBColor(red: 0.0, green: 0.95, blue: 0.95)),
        ColorPalettePreset(id: "neon_magenta", name: "Neon Magenta", color: RGBColor(red: 1.0, green: 0.05, blue: 0.65)),
        ColorPalettePreset(id: "synthwave_purple", name: "Synthwave Violet", color: RGBColor(red: 0.6, green: 0.0, blue: 1.0)),
        ColorPalettePreset(id: "toxic_green", name: "Toxic Acid Green", color: RGBColor(red: 0.1, green: 1.0, blue: 0.2)),
        ColorPalettePreset(id: "amber_orange", name: "Sunset Amber", color: RGBColor(red: 1.0, green: 0.45, blue: 0.0)),
        ColorPalettePreset(id: "crimson_red", name: "Crimson Red", color: RGBColor(red: 1.0, green: 0.08, blue: 0.1)),
        ColorPalettePreset(id: "gold_yellow", name: "Solar Gold", color: RGBColor(red: 1.0, green: 0.85, blue: 0.0)),
        ColorPalettePreset(id: "pure_white", name: "Glacier White", color: RGBColor(red: 1.0, green: 1.0, blue: 1.0)),
        ColorPalettePreset(id: "stealth_off", name: "Stealth Dark (Off)", color: RGBColor(red: 0.0, green: 0.0, blue: 0.0))
    ]
}

public struct LightbarConfiguration: Codable, Equatable {
    public var mode: LightingMode = .staticColor
    public var staticColor: RGBColor = RGBColor(red: 0.0, green: 0.38, blue: 1.0)
    public var rainbowSpeed: Double = 1.0       // Speed multiplier (0.1 ... 5.0)
    public var rainbowSaturation: Double = 1.0  // 0.0 ... 1.0
    public var rainbowBrightness: Double = 1.0  // 0.0 ... 1.0
    public var breathingSpeed: Double = 1.0     // Cycles per second
    public var playerLEDMode: PlayerLEDMode = .player1
    public var playerLEDBrightness: PlayerLEDBrightness = .medium
    public var micLEDMode: MicLEDMode = .off

    public init() {}
}

extension LightbarConfiguration {
    /// Resolves the player indicator row to a raw bitmask.
    ///
    /// `level` and `beat` come from the audio analysis; they only reach the row
    /// when `music` says the music is driving it, and otherwise the fixed
    /// player pattern applies.
    public func playerLEDMask(
        music: MusicSyncConfiguration = MusicSyncConfiguration(),
        level: Float = 0,
        beat: Float = 0,
        kick: Float = 0,
        snare: Float = 0
    ) -> UInt8 {
        // "Off" brightness darkens the row whatever the pattern says.
        guard !playerLEDBrightness.extinguishesLEDs else { return 0 }
        return music.playerLEDMask(level: level, beat: beat, kick: kick, snare: snare) ?? playerLEDMode.bitmask
    }
}
