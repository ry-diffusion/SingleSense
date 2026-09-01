import SwiftUI
import AppKit

@main
struct SingleSenseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
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
        
        MenuBarExtra("SingleSense", systemImage: "gamecontroller.fill") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app runs as a full regular GUI app with Dock icon and windows
        NSApp.setActivationPolicy(.regular)
        
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
