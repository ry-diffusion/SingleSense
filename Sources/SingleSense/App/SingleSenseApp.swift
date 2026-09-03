import SwiftUI
import AppKit

@main
struct SingleSenseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var controllerState = DualSenseManager.shared.controllerState
    
    var body: some Scene {
        WindowGroup("SingleSense", id: "main") {
            MainView()
        }
        .defaultSize(width: 960, height: 680)
        .windowStyle(DefaultWindowStyle())
        .windowToolbarStyle(UnifiedWindowToolbarStyle())
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .appInfo) {
                Button("About SingleSense") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.applicationName: "SingleSense",
                            NSApplication.AboutPanelOptionKey.applicationVersion: "1.0.0",
                            NSApplication.AboutPanelOptionKey.version: "1.0.0"
                        ]
                    )
                }
            }
        }
        
        MenuBarExtra {
            MenuBarView()
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.menu)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        if controllerState.isConnected {
            let percentage = Int(controllerState.batteryLevel * 100)
            HStack(spacing: 3) {
                Image(systemName: "gamecontroller.fill")
                Text("\(percentage)%")
                Image(systemName: batterySymbolName)
            }
        } else {
            Image(systemName: "gamecontroller")
        }
    }

    private var batterySymbolName: String {
        let level = controllerState.batteryLevel
        if controllerState.isBatteryCharging {
            return "battery.100percent.bolt"
        }
        if level > 0.85 {
            return "battery.100percent"
        } else if level > 0.60 {
            return "battery.75percent"
        } else if level > 0.35 {
            return "battery.50percent"
        } else if level > 0.10 {
            return "battery.25percent"
        } else {
            return "battery.0percent"
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app runs as a full regular GUI app with Dock icon and windows
        NSApp.setActivationPolicy(.regular)
        
        PermissionMonitor.shared.start()
        DualSenseManager.shared.start()
        
        // Bring window to front and activate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where !(window is NSPanel) && window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                window.center()
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        DualSenseManager.shared.stop()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where !(window is NSPanel) && window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running in Menu Bar when main window is closed
    }
}
