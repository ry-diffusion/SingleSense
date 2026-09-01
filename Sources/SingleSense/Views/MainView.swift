import SwiftUI

public enum NavigationItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case lightbar = "Lightbar & LEDs"
    case triggers = "Adaptive Triggers"
    case haptics = "Haptics & Vibration"
    case motion = "Motion & Gyro"
    case trackpad = "Trackpad"
    case profiles = "Profiles"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .dashboard: return "gauge.medium"
        case .lightbar: return "rainbow"
        case .triggers: return "scope"
        case .haptics: return "waveform.path.ecg"
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
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            List(NavigationItem.allCases, selection: $selectedItem) { item in
                NavigationLink(value: item) {
                    Label(item.rawValue, systemImage: item.iconName)
                        .font(.system(size: 13, weight: .medium))
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
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if controllerState.isConnected {
                        Text("\(Int(controllerState.batteryLevel * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
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
                case .triggers:
                    TriggerStudioView()
                case .haptics:
                    HapticsLabView()
                case .motion:
                    MotionSensorView()
                case .trackpad:
                    TrackpadView()
                case .profiles:
                    ProfilesView()
                }
            }
            .navigationTitle(selectedItem?.rawValue ?? "SingleSense")
        }
        .frame(minWidth: 850, minHeight: 620)
    }
}
