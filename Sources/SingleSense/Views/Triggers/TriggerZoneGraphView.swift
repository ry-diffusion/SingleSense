import SwiftUI

public struct TriggerZoneGraphView: View {
    @Binding var zones: [Float]
    let currentTriggerPosition: Float // 0.0 ... 1.0
    let isVibration: Bool
    let onChange: () -> Void
    
    public init(zones: Binding<[Float]>, currentTriggerPosition: Float, isVibration: Bool = false, onChange: @escaping () -> Void) {
        self._zones = zones
        self.currentTriggerPosition = currentTriggerPosition
        self.isVibration = isVibration
        self.onChange = onChange
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isVibration ? "10-Zone Positional Vibration Profile" : "10-Zone Positional Resistance Profile")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("Zone 0 (Start) → Zone 9 (Bottom Out)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            // Interactive 10-Zone Bars
            ZStack(alignment: .bottomLeading) {
                // Zone Bars Grid
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<10, id: \.self) { index in
                        let value = zones.indices.contains(index) ? zones[index] : 0.0
                        
                        VStack(spacing: 4) {
                            // Value Bar
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(height: 100)
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: isVibration ? [.orange, .red] : [.blue, .cyan],
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .frame(height: max(4, CGFloat(value) * 100))
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { gesture in
                                        let height = max(0, min(100, 100 - gesture.location.y))
                                        let newValue = Float(height / 100.0)
                                        if zones.indices.contains(index) {
                                            zones[index] = newValue
                                            onChange()
                                        }
                                    }
                            )
                            
                            // Zone Label
                            Text("Z\(index)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                            
                            // Percent
                            Text("\(Int(value * 100))%")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(height: 140)
                
                // Real-time Trigger Position Cursor Line
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 2.5, height: 100)
                        .shadow(color: Color.yellow.opacity(0.8), radius: 4)
                        .position(
                            x: geo.size.width * CGFloat(currentTriggerPosition),
                            y: 50
                        )
                }
                .frame(height: 100)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
            .cornerRadius(10)
        }
    }
}
