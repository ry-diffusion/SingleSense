import SwiftUI
import AppKit

public struct MenuBarView: View {
    @ObservedObject var manager = DualSenseManager.shared
    @ObservedObject var profileStorage = ProfileStorage.shared
    @Environment(\.openWindow) private var openWindow
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Open Main Window Button
            Button(action: {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
                for window in NSApp.windows where !(window is NSPanel) && window.canBecomeMain {
                    window.makeKeyAndOrderFront(nil)
                }
            }) {
                HStack {
                    Image(systemName: "macwindow.badge.plus")
                    Text("Open Single Sense Window")
                        .fontWeight(.bold)
                }
            }
            
            Divider()
            
            // Connection Status
            HStack {
                Circle()
                    .fill(manager.controllerState.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Text(manager.controllerState.isConnected ? manager.controllerState.controllerName : "No Controller Detected")
                    .font(.system(size: 12, weight: .bold))
                
                Spacer()
                
                if manager.controllerState.isConnected {
                    Text("\(Int(manager.controllerState.batteryLevel * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Rainbow Mode Quick Toggle
            Button(action: {
                if manager.lightbarConfig.mode == .rainbow {
                    manager.lightbarConfig.mode = .staticColor
                } else {
                    manager.lightbarConfig.mode = .rainbow
                }
                manager.applyLightbarConfiguration()
            }) {
                HStack {
                    Image(systemName: "rainbow")
                    Text(manager.lightbarConfig.mode == .rainbow ? "Disable Rainbow (Static)" : "Enable 60 FPS Rainbow")
                }
            }
            
            // Quick Color Palettes Menu
            Menu("Quick Lightbar Color") {
                ForEach(ColorPresets.list) { preset in
                    Button(preset.name) {
                        manager.lightbarConfig.mode = .staticColor
                        manager.lightbarConfig.staticColor = preset.color
                        manager.applyLightbarConfiguration()
                    }
                }
            }
            
            // Quick Profiles Menu
            Menu("Switch Profile") {
                ForEach(profileStorage.profiles) { profile in
                    Button(profile.name) {
                        profileStorage.activeProfileId = profile.id
                        manager.applyProfile(profile)
                    }
                }
            }
            
            // Reset Triggers
            Button("Reset Triggers to Standard") {
                manager.leftTriggerConfig.mode = .off
                manager.rightTriggerConfig.mode = .off
                manager.applyTriggerConfiguration()
            }
            
            Divider()
            
            Button("Quit Single Sense") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(8)
        .frame(width: 240)
    }
}
