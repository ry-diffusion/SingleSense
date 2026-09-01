import SwiftUI

public struct BatteryIndicatorView: View {
    let level: Float // 0.0 ... 1.0
    let isCharging: Bool
    
    public init(level: Float, isCharging: Bool) {
        self.level = level
        self.isCharging = isCharging
    }
    
    private var batteryColor: Color {
        if isCharging { return .green }
        if level > 0.5 { return .green }
        if level > 0.2 { return .yellow }
        return .red
    }
    
    private var batteryIconName: String {
        if isCharging { return "battery.100.bolt" }
        if level > 0.85 { return "battery.100" }
        if level > 0.6 { return "battery.75" }
        if level > 0.35 { return "battery.50" }
        if level > 0.1 { return "battery.25" }
        return "battery.0"
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: batteryIconName)
                .foregroundColor(batteryColor)
                .font(.system(size: 14, weight: .semibold))
            
            Text("\(Int(level * 100))%")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(6)
    }
}

public struct ConnectionBadgeView: View {
    let isConnected: Bool
    let type: ConnectionType
    let modelName: String
    
    public init(isConnected: Bool, type: ConnectionType, modelName: String) {
        self.isConnected = isConnected
        self.type = type
        self.modelName = modelName
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
                .shadow(color: isConnected ? Color.green.opacity(0.6) : Color.clear, radius: 4)
            
            if isConnected {
                HStack(spacing: 4) {
                    Image(systemName: type.iconName)
                        .font(.system(size: 12))
                    Text("\(type.rawValue)")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.secondary)
            } else {
                Text("Disconnected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(6)
    }
}
