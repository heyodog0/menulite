import AppKit
import SwiftUI
import Combine

/// Owns the menu-bar status item and the glass panel. We size the window
/// ourselves (AppKit) so the NSGlassEffectView resizes natively between the
/// home and detail layouts.
@MainActor
final class StatusController: NSObject, NSWindowDelegate {
    private let statusItem: NSStatusItem
    private let state = AppState()
    private let panel: GlassPanel
    private var cancellables: Set<AnyCancellable> = []

    private let width: CGFloat = 264
    private let homeHeight: CGFloat = 306
    private let detailHeight: CGFloat = 470
    private var originX: CGFloat = 0
    private var pinnedTopY: CGFloat = 0

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panel = GlassPanel(content: RootView().environmentObject(state))
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

        // Animate the panel between home and detail heights when the drill-in changes.
        state.$selected
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] sel in self?.resize(for: sel, animated: true) }
            .store(in: &cancellables)
    }

    private func heightFor(_ sel: Resource?) -> CGFloat {
        sel == nil ? homeHeight : detailHeight
    }

    @objc private func togglePanel() {
        panel.isVisible ? close() : open()
    }

    private func open() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.frame
        let screen = buttonWindow.screen ?? NSScreen.main

        let h = heightFor(state.selected)
        var x = buttonFrame.midX - width / 2
        if let vis = screen?.visibleFrame {
            x = min(max(x, vis.minX + 6), vis.maxX - width - 6)
        }
        originX = x
        pinnedTopY = buttonFrame.minY      // glass top hugs the menu bar

        panel.setFrame(NSRect(x: x, y: pinnedTopY - h, width: width, height: h), display: false)

        state.panelVisible = false
        panel.alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)

        DispatchQueue.main.async { [weak self] in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                self?.state.panelVisible = true
            }
        }
    }

    private func resize(for sel: Resource?, animated: Bool) {
        guard panel.isVisible else { return }
        let h = heightFor(sel)
        let newFrame = NSRect(x: originX, y: pinnedTopY - h, width: width, height: h)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.34
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: true)
        }
    }

    private func close() {
        statusItem.button?.highlight(false)
        withAnimation(.easeIn(duration: 0.14)) { state.panelVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.panel.orderOut(nil)
            self?.state.selected = nil   // reset to home for next open
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if panel.isVisible { close() }
    }
}
