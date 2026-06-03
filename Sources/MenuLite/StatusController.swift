import AppKit
import SwiftUI
import Combine

/// Owns the menu-bar status item and a custom glass panel that drops flush
/// under the menu bar with a subtle open animation.
@MainActor
final class StatusController: NSObject, NSWindowDelegate {
    private let statusItem: NSStatusItem
    private let state = AppState()
    private let panel: GlassPanel
    private var cancellables: Set<AnyCancellable> = []
    private var pinnedTopY: CGFloat = 0   // screen Y the panel's top stays glued to

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panel = GlassPanel(
            content: RootView().environmentObject(state)
        )
        super.init()
        panel.delegate = self

        if let button = statusItem.button {
            button.title = state.menuBarLabel
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(togglePanel)
        }

        // Keep the menu-bar title live.
        state.$cpu.combineLatest(state.$memUsed)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.statusItem.button?.title = self?.state.menuBarLabel ?? ""
            }
            .store(in: &cancellables)
    }

    @objc private func togglePanel() {
        panel.isVisible ? close() : open()
    }

    private func open() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.frame
        let screen = buttonWindow.screen ?? NSScreen.main

        panel.forceLayout()
        let size = panel.frame.size

        // Center under the status item; clamp to the screen; sit flush under the bar.
        var x = buttonFrame.midX - size.width / 2
        if let vis = screen?.visibleFrame {
            x = min(max(x, vis.minX + 6), vis.maxX - size.width - 6)
        }
        // The visible card is inset by GlassPanel.shadowPad, so overlap that much
        // to make the card hug the menu bar.
        let topY = buttonFrame.minY + GlassPanel.shadowPad
        pinnedTopY = topY
        let finalOrigin = CGPoint(x: x, y: topY - size.height)

        // Show at full window alpha; the fade/scale happens in SwiftUI for a
        // smooth Liquid-Glass feel. Start hidden, then animate visible.
        state.panelVisible = false
        panel.alphaValue = 1
        panel.setFrameOrigin(finalOrigin)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)

        DispatchQueue.main.async { [weak self] in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                self?.state.panelVisible = true
            }
        }
    }

    private func close() {
        statusItem.button?.highlight(false)
        withAnimation(.easeIn(duration: 0.14)) { state.panelVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.panel.orderOut(nil)
            self?.state.selected = nil   // reset to home next open
        }
    }

    // Dismiss when the user clicks away.
    func windowDidResignKey(_ notification: Notification) {
        if panel.isVisible { close() }
    }

    // Keep the top edge pinned under the menu bar as content height changes.
    func windowDidResize(_ notification: Notification) {
        guard panel.isVisible, pinnedTopY > 0 else { return }
        var f = panel.frame
        if abs(f.maxY - pinnedTopY) > 0.5 {
            f.origin.y = pinnedTopY - f.height
            panel.setFrame(f, display: true)
        }
    }
}
