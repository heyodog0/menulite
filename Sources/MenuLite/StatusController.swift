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

    private let width: CGFloat = panelWidth   // 264
    private let minHeight: CGFloat = 160
    private let maxHeight: CGFloat = 560
    private let fallbackHeight: CGFloat = 340   // before the content first measures
    private var originX: CGFloat = 0
    private var pinnedTopY: CGFloat = 0
    // Resize instantly until the panel finishes opening, then animate height
    // changes (home ↔ detail, tab switches) by growing/shrinking the clear window
    // around the SwiftUI glass.
    private var panelSettled = false

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

        // Live-update the menu-bar rings as CPU / memory change. Only redraw when
        // the *rendered* ring actually changes (rounded to whole %): the glyph is
        // a few px wide, so sub-percent jitter every 2s would be wasted drawing.
        state.$cpu.combineLatest(state.$memUsed)
            .map { [weak self] _, _ in
                CGPoint(x: (self?.state.cpu ?? 0).rounded(),
                        y: (self?.state.memPct ?? 0).rounded())
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.statusItem.button?.image =
                    self.dualRingGlyph(cpuPct: self.state.cpu, memPct: self.state.memPct)
            }
            .store(in: &cancellables)

        // The SwiftUI glass publishes its full height; keep the transparent window
        // at least that tall so it never clips the glass. Resizing is invisible
        // (the window's margins are clear), so there's no frame animation to drag
        // the content — all motion is the SwiftUI glass animating its own height.
        state.$panelContentHeight
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncWindowSize() }
            .store(in: &cancellables)

        // Let SwiftUI (tap outside the glass) dismiss the panel.
        state.closePanel = { [weak self] in self?.close() }
    }

    private func panelHeight() -> CGFloat {
        let h = state.panelContentHeight
        guard h > 0 else { return fallbackHeight }
        return min(max(h, minHeight), maxHeight)
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

        let h = panelHeight()
        var x = buttonFrame.midX - width / 2
        if let vis = screen?.visibleFrame {
            x = min(max(x, vis.minX + 6), vis.maxX - width - 6)
        }
        originX = x
        pinnedTopY = buttonFrame.minY      // glass top hugs the menu bar

        setWindow(h)

        // The window is clear; the SwiftUI glass fades + scales up from the top
        // (Control-Center "blurred → focus"). Start hidden.
        panelSettled = false
        state.panelVisible = false
        panel.alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Content has laid out — cover its true height before it animates in.
            self.syncWindowSize()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.state.panelVisible = true
            }
            self.panelSettled = true
        }
    }

    /// Keep the transparent window tall enough to contain the SwiftUI glass, top
    /// edge pinned. Growing is applied immediately (the new space is clear, so it's
    /// invisible, and gives the glass room to animate into). Shrinking waits for the
    /// glass to finish collapsing, then tightens — also invisible. The window is
    /// only ever set instantly; the *glass* is what animates, in SwiftUI.
    private func syncWindowSize() {
        guard panel.isVisible else { return }
        let target = panelHeight()
        let current = panel.frame.height
        guard abs(target - current) > 0.5 else { return }
        if !panelSettled || target > current {
            setWindow(target)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
                guard let self, self.panel.isVisible else { return }
                self.setWindow(self.panelHeight())
            }
        }
    }

    private func setWindow(_ h: CGFloat) {
        panel.setFrame(NSRect(x: originX, y: pinnedTopY - h, width: width, height: h),
                       display: true)
    }

    private func close() {
        statusItem.button?.highlight(false)
        panel.makeFirstResponder(nil)
        panelSettled = false

        // The SwiftUI glass fades + scales down toward the menu bar; once it's
        // gone, order the (clear) window out and reset to the home screen.
        withAnimation(.easeIn(duration: 0.16)) { state.panelVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.state.selected = nil
        }
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
                          percent: memPct, color: self.nsPressureColor(self.state.memPressure))
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

    private func nsPressureColor(_ level: Int) -> NSColor {
        switch level {
        case 4:  return .systemRed
        case 2:  return .systemOrange
        default: return .systemBlue
        }
    }
}
