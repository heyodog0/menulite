import SwiftUI
import AppKit

@main
struct MenuLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(state)
        } label: {
            // Compact live readout in the menu bar: CPU% and Memory%.
            Text(state.menuBarLabel)
        }
        .menuBarExtraStyle(.window)   // .window lets the dropdown use sliders/toggles
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar agent: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
    }
}
