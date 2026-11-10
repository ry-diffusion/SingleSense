import SwiftUI

public enum NavigationItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case lightbar = "Lightbar & LEDs"
    case musicSync = "Music Sync"
    case triggers = "Adaptive Triggers"
    case haptics = "Haptics & Vibration"
    case speaker = "Speaker & Subwoofer"
    case motion = "Motion & Gyro"
    case trackpad = "Trackpad"
    case profiles = "Profiles"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .dashboard: return "gauge.medium"
        case .lightbar: return "rainbow"
        case .musicSync: return "waveform"
        case .triggers: return "scope"
        case .haptics: return "waveform.path.ecg"
        case .speaker: return "hifispeaker.fill"
        case .motion: return "gyroscope"
        case .trackpad: return "cursorarrow.rays"
        case .profiles: return "square.stack.3d.up.fill"
        }
    }
}

public struct MainView: View {
    @State private var selectedItem: NavigationItem? = .dashboard
    @ObservedObject var manager = DualSenseManager.shared
    // ControllerState is a reference type, so @Published on the manager never
    // fires for changes *inside* it. Observing it directly is what keeps live
    // input (trigger pressure, battery, telemetry) flowing into the view.
    @ObservedObject var controllerState = DualSenseManager.shared.controllerState
    @ObservedObject var rainbowEngine = RainbowEngine.shared
    @ObservedObject var audioEngine = AudioReactiveEngine.shared
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            List(NavigationItem.allCases, selection: $selectedItem) { item in
                NavigationLink(value: item) {
                    Label(item.rawValue, systemImage: item.iconName)
                        .font(.body.weight(.medium))
                }
            }
            .listStyle(SidebarListStyle())
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
            .safeAreaInset(edge: .bottom) {
                // Bottom Controller Status Pill
                HStack(spacing: 8) {
                    Circle()
                        .fill(controllerState.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text(controllerState.isConnected ? controllerState.model.shortName : "No Controller")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if controllerState.isConnected {
                        Text("\(Int(controllerState.batteryLevel * 100))%")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .cornerRadius(8)
                .padding(10)
            }
        } detail: {
            Group {
                switch selectedItem ?? .dashboard {
                case .dashboard:
                    DashboardView()
                case .lightbar:
                    LightbarStudioView()
                case .musicSync:
                    MusicSyncView()
                case .triggers:
                    TriggerStudioView()
                case .haptics:
                    HapticsLabView()
                case .speaker:
                    SpeakerView()
                case .motion:
                    MotionSensorView()
                case .trackpad:
                    TrackpadView()
                case .profiles:
                    ProfilesView()
                }
            }
            .navigationTitle(selectedItem?.rawValue ?? "Single Sense")
            .background(musicSyncBackground)
        }
        .frame(minWidth: 850, minHeight: 620)
        .background(musicSyncBackground)
    }

    @ViewBuilder
    private var musicSyncBackground: some View {
        if manager.musicSyncConfig.isEnabled {
            let primary = rainbowEngine.currentDisplayColor.color
            let beat = Double(audioEngine.displayLevels.beat)
            let overall = Double(audioEngine.displayLevels.overall)
            let bass = Double(audioEngine.displayLevels.bass)
            let treble = Double(audioEngine.displayLevels.treble)

            ZStack {
                Color(NSColor.windowBackgroundColor)

                // Top-leading glow: follows the lightbar's current live color and pulses on beat
                RadialGradient(
                    gradient: Gradient(colors: [
                        primary.opacity(0.20 + beat * 0.15),
                        primary.opacity(0.06),
                        Color.clear
                    ]),
                    center: .topLeading,
                    startRadius: 50,
                    endRadius: 600
                )

                // Bottom-trailing glow: harmonic accent driven by treble and overall music loudness
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(
                            red: max(0.05, 0.15 + treble * 0.5),
                            green: max(0.1, 0.2 + bass * 0.4),
                            blue: max(0.3, 0.8 + treble * 0.2)
                        ).opacity(0.18 + overall * 0.12),
                        Color.clear
                    ]),
                    center: .bottomTrailing,
                    startRadius: 80,
                    endRadius: 650
                )

                // Linear wash connecting both sides
                LinearGradient(
                    gradient: Gradient(colors: [
                        primary.opacity(0.08 + beat * 0.08),
                        Color.clear,
                        primary.opacity(0.04)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .animation(.easeInOut(duration: 0.15), value: rainbowEngine.currentDisplayColor)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: audioEngine.displayLevels.beat)
            .ignoresSafeArea()
        }
    }
}
