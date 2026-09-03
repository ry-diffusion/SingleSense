import SwiftUI

public struct TriggerPresetsView: View {
    let onSelectPreset: (TriggerPreset) -> Void
    
    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 12)
    ]
    
    public init(onSelectPreset: @escaping (TriggerPreset) -> Void) {
        self.onSelectPreset = onSelectPreset
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weapon & Mechanical Presets")
                .font(.headline.weight(.bold))
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(TriggerPresets.all) { preset in
                    Button(action: {
                        onSelectPreset(preset)
                    }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: preset.iconName)
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 24, height: 24)
                                
                                Text(preset.name)
                                    .font(.headline.weight(.bold))
                                    .foregroundColor(.primary)
                                
                                Spacer(minLength: 0)
                            }
                            
                            Text(preset.description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            HStack(spacing: 8) {
                                Text("L2: \(preset.leftConfig.mode.rawValue)")
                                    .font(.caption2.monospaced().weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(4)
                                
                                Text("R2: \(preset.rightConfig.mode.rawValue)")
                                    .font(.caption2.monospaced().weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(4)
                            }
                            .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}
