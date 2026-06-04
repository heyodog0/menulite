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
    private let homeHeight: CGFloat = 274
    private let detailHeight: CGFloat = 470
    private var originX: CGFloat = 0
    private var pinnedTopY: CGFloat = 0

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panel = GlassPanel(content: RootView().environmentObject(state))
        super.init()
        panel.delegate = self

        if let button = statusItem.button {
            button.image = dualRingGlyph(cpuPct: state.cpu, memPct: state.memPct)
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Enable launch-at-login once (the user asked for it); the right-click
        // menu lets them turn it off later without it re-enabling each launch.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "loginItemConfigured") {
            LoginItem.forceEnable()   // register THIS bundle's location
            defaults.set(true, forKey: "loginItemConfigured")
        }

        // Live-update the menu-bar rings as CPU / memory change.
        state.$cpu.combineLatest(state.$memUsed)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.statusItem.button?.image =
                    self.dualRingGlyph(cpuPct: self.state.cpu, memPct: self.state.memPct)
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

    @objc private func statusButtonClicked() {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        isRight ? showMenu() : togglePanel()
    }

    private func togglePanel() {
        panel.isVisible ? close() : open()
    }

    private func showMenu() {
        if panel.isVisible { close() }
        let menu = NSMenu()
        let login = NSMenuItem(title: "Launch at Login",
                               action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit MenuLite",
                              action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        if let button = statusItem.button {
            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: button.bounds.maxY + 5), in: button)
        }
    }

    @objc private func toggleLogin() { LoginItem.setEnabled(!LoginItem.isEnabled) }
    @objc private func quitApp() { NSApp.terminate(nil) }

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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.62)) {   // snappy bounce
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

        // Collapse the glass panel upward toward the menu bar while fading —
        // like Control Center's dismiss (top edge stays pinned, it shrinks up).
        let f = panel.frame
        let s: CGFloat = 0.90
        let nw = f.width * s, nh = f.height * s
        let shrunk = NSRect(x: f.midX - nw / 2, y: f.maxY - nh, width: nw, height: nh)

        withAnimation(.easeIn(duration: 0.18)) { state.panelVisible = false }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
            panel.animator().setFrame(shrunk, display: true)
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1          // reset for next open
            self.state.selected = nil          // reset to home
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        if panel.isVisible { close() }
    }

    // MARK: - menu-bar ring glyphs

    /// Two side-by-side rings: CPU (left) and memory (right).
    private func dualRingGlyph(cpuPct: Double, memPct: Double) -> NSImage {
        let dim: CGFloat = 16, gap: CGFloat = 4
        let size = NSSize(width: dim * 2 + gap, height: dim)
        let img = NSImage(size: size, flipped: false) { _ in
            self.drawRing(in: NSRect(x: 0, y: 0, width: dim, height: dim),
                          percent: cpuPct, color: self.nsLoadColor(cpuPct))
            self.drawRing(in: NSRect(x: dim + gap, y: 0, width: dim, height: dim),
                          percent: memPct, color: self.nsMemColor(memPct))
            return true
        }
        img.isTemplate = false   // keep our green/orange/red color
        return img
    }

    /// One ring that fills clockwise from 12 o'clock, drawn in `color`.
    private func drawRing(in box: NSRect, percent: Double, color: NSColor) {
        let line: CGFloat = 2.4
        let f = CGFloat(max(0, min(1, percent / 100)))
        let inset = line / 2 + 0.5
        let rect = box.insetBy(dx: inset, dy: inset)
        let center = NSPoint(x: box.midX, y: box.midY)
        let radius = rect.width / 2

        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = line
        NSColor(white: 0.55, alpha: 0.5).setStroke()
        track.stroke()

        if f > 0.001 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius,
                          startAngle: 90, endAngle: 90 - 360 * f, clockwise: true)
            arc.lineWidth = line
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()
        }
    }

    private func nsLoadColor(_ pct: Double) -> NSColor {
        switch pct {
        case ..<60: return .systemGreen
        case ..<85: return .systemOrange
        default:    return .systemRed
        }
    }

    private func nsMemColor(_ pct: Double) -> NSColor {
        switch pct {
        case ..<85: return .systemBlue
        case ..<95: return .systemOrange
        default:    return .systemRed
        }
    }
}
