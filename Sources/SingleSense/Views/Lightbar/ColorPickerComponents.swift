import SwiftUI

public struct RGBColorSlidersView: View {
    @Binding var color: RGBColor
    let onChange: (RGBColor) -> Void
    
    public init(color: Binding<RGBColor>, onChange: @escaping (RGBColor) -> Void) {
        self._color = color
        self.onChange = onChange
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Red Slider
            HStack(spacing: 12) {
                Text("R")
                    .font(.headline.monospaced().weight(.bold))
                    .foregroundColor(.red)
                    .frame(width: 18)
                
                Slider(
                    value: Binding(
                        get: { color.red },
                        set: { color.red = $0; onChange(color) }
                    ),
                    in: 0.0...1.0
                )
                .accentColor(.red)
                
                Text("\(color.redByte)")
                    .font(.callout.monospaced().weight(.medium))
                    .frame(width: 36, alignment: .trailing)
            }
            
            // Green Slider
            HStack(spacing: 12) {
                Text("G")
                    .font(.headline.monospaced().weight(.bold))
                    .foregroundColor(.green)
                    .frame(width: 18)
                
                Slider(
                    value: Binding(
                        get: { color.green },
                        set: { color.green = $0; onChange(color) }
                    ),
                    in: 0.0...1.0
                )
                .accentColor(.green)
                
                Text("\(color.greenByte)")
                    .font(.callout.monospaced().weight(.medium))
                    .frame(width: 36, alignment: .trailing)
            }
            
            // Blue Slider
            HStack(spacing: 12) {
                Text("B")
                    .font(.headline.monospaced().weight(.bold))
                    .foregroundColor(.blue)
                    .frame(width: 18)
                
                Slider(
                    value: Binding(
                        get: { color.blue },
                        set: { color.blue = $0; onChange(color) }
                    ),
                    in: 0.0...1.0
                )
                .accentColor(.blue)
                
                Text("\(color.blueByte)")
                    .font(.callout.monospaced().weight(.medium))
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}

public struct ColorPresetsGridView: View {
    @Binding var selectedColor: RGBColor
    let onSelect: (RGBColor) -> Void
    
    private let columns = [
        GridItem(.adaptive(minimum: 120), spacing: 10)
    ]
    
    public init(selectedColor: Binding<RGBColor>, onSelect: @escaping (RGBColor) -> Void) {
        self._selectedColor = selectedColor
        self.onSelect = onSelect
    }
    
    public var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(ColorPresets.list) { preset in
                Button(action: {
                    selectedColor = preset.color
                    onSelect(preset.color)
                }) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(preset.color.color)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: preset.color.color.opacity(0.6), radius: 3)
                        
                        Text(preset.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedColor == preset.color ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedColor == preset.color ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}
