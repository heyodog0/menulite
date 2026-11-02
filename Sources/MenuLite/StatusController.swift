// © 2026 Ryan Truong. All rights reserved. Not licensed for copying, porting or
// reimplementation, by hand or with AI tools. See LICENSE.

import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox

/// Owns the menu-bar status item and the glass panel. The panel's window is a
/// clear canvas kept at least as tall as the SwiftUI glass (plus a shadow
/// margin); all visible resizing happens in SwiftUI.
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
    /// Bumped on every open/close so a finished close fade can tell it's stale.
    private var transition = 0
    /// Last menu-bar look drawn, so the 2s sample only redraws on a change.
    private var lastItemKey = ""
    /// ⌃⌥M opens the panel, ⌃⌥S toggles keep-awake, ⌃⌥K starts keyboard cleaning
    /// (toggle in the right-click menu).
    private var hotKeys: [HotKey] = []
    private var shortcutsEnabled = UserDefaults.standard.object(forKey: "shortcutsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(shortcutsEnabled, forKey: "shortcutsEnabled"); syncHotKeys() }
    }

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panel = GlassPanel(content: RootView().environmentObject(state))
        super.init()
        panel.delegate = self

        if let button = statusItem.button {
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

        // Live-update the menu-bar item: the rings, the optional readout beside
        // them, and the keep-awake mark. Only redraw when what's *rendered*
        // changes (rings rounded to whole %): sub-percent jitter every 2s would
        // be wasted drawing.
        updateStatusItem()
        state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        syncHotKeys()

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

        // Scriptable toggle, for screenshotting the panel without a click:
        // Scripts/toggle-panel.swift posts this.
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.heyodog0.menulite.togglePanel"),
            object: nil, queue: .main
        ) { [weak self] n in
            MainActor.assumeIsolated {
                // An optional screen name ("cpu", "memory", …) opens on it.
                if let name = n.object as? String {
                    self?.state.selected = Resource.allCases.first { "\($0)" == name }
                }
                self?.togglePanel()
            }
        }
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
        let info = Bundle.main.infoDictionary ?? [:]
        let stamp = NSMenuItem(
            title: "\(info["CFBundleShortVersionString"] ?? "") · \(info["CFBundleVersion"] ?? "") · \(info["BuildDate"] ?? "")",
            action: nil, keyEquivalent: "")
        stamp.isEnabled = false
        menu.addItem(stamp)
        menu.addItem(.separator())
        let stat = NSMenuItem(title: "Menu Bar Shows", action: nil, keyEquivalent: "")
        let statMenu = NSMenu()
        for option in MenuBarStat.allCases where option != .battery || state.battery != nil {
            let item = NSMenuItem(title: option.title, action: #selector(pickMenuBarStat(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = state.menuBarStat == option ? .on : .off
            statMenu.addItem(item)
        }
        stat.submenu = statMenu
        menu.addItem(stat)
        let shortcuts = NSMenuItem(title: "Shortcuts: ⌃⌥M Panel · ⌃⌥S Keep Awake · ⌃⌥K Clean",
                                   action: #selector(toggleShortcuts), keyEquivalent: "")
        shortcuts.target = self
        shortcuts.state = shortcutsEnabled && !hotKeys.isEmpty ? .on : .off
        menu.addItem(shortcuts)
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
    @objc private func toggleShortcuts() { shortcutsEnabled.toggle() }

    @objc private func pickMenuBarStat(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let stat = MenuBarStat(rawValue: raw) {
            state.menuBarStat = stat
        }
    }

    private func syncHotKeys() {
        hotKeys = []
        guard shortcutsEnabled else { return }
        let mods = controlKey | optionKey
        if let k = HotKey(keyCode: kVK_ANSI_M, modifiers: mods, action: { [weak self] in
            MainActor.assumeIsolated { self?.togglePanel() } }) { hotKeys.append(k) }
        if let k = HotKey(keyCode: kVK_ANSI_S, modifiers: mods, action: { [weak self] in
            MainActor.assumeIsolated { self?.state.toggleSleep() } }) { hotKeys.append(k) }
        // Start only: a paw on the keys shouldn't end cleaning — Done does.
        if let k = HotKey(keyCode: kVK_ANSI_K, modifiers: mods, action: { [weak self] in
            MainActor.assumeIsolated {
                guard let state = self?.state, !state.cleaning else { return }
                state.toggleCleaning()
            } }) { hotKeys.append(k) }
    }

    /// Rings, then the chosen readout as the button's title (so macOS colors
    /// it for the bar like any menu-bar text).
    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let text = state.menuBarText
        let key = "\(state.cpu.rounded())|\(state.memPct.rounded())|\(state.memPressure)|\(state.preventSleep)|\(text)"
        guard key != lastItemKey else { return }
        lastItemKey = key
        button.image = dualRingGlyph(cpuPct: state.cpu, memPct: state.memPct, awake: state.preventSleep)
        button.imagePosition = text.isEmpty ? .imageOnly : .imageLeading
        button.attributedTitle = NSAttributedString(string: text.isEmpty ? "" : " " + text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        ])
    }

    private func open() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.frame
        let screen = buttonWindow.screen ?? NSScreen.main

        let h = panelHeight()
        var x = buttonFrame.midX - width / 2   // glass left edge
        if let vis = screen?.visibleFrame {
            x = min(max(x, vis.minX + 6), vis.maxX - width - 6)
        }
        originX = x - shadowMargin
        pinnedTopY = buttonFrame.minY      // glass top hugs the menu bar

        setWindow(h)

        // Start transparent: the window's alpha fades the glass in (its backdrop
        // blur fades cleanly that way), while SwiftUI settles the content inside.
        transition += 1
        panelSettled = false
        state.panelVisible = false
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Content has laid out — cover its true height before it animates in.
            self.syncWindowSize()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Motion.openDuration * 0.75
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.panel.animator().alphaValue = 1
            }
            withAnimation(Motion.open) { self.state.panelVisible = true }
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
        let current = panel.frame.height - shadowMargin
        guard abs(target - current) > 0.5 else { return }
        if !panelSettled || target > current {
            setWindow(target)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Motion.duration + 0.04) { [weak self] in
                guard let self, self.panel.isVisible else { return }
                self.setWindow(self.panelHeight())
            }
        }
    }

    private func setWindow(_ h: CGFloat) {
        let h = h + shadowMargin
        panel.setFrame(NSRect(x: originX, y: pinnedTopY - h,
                              width: width + 2 * shadowMargin, height: h),
                       display: true)
    }

    private func close() {
        statusItem.button?.highlight(false)
        panel.makeFirstResponder(nil)
        panelSettled = false

        // Fade the window (and so the glass) out while the content lifts away;
        // when the fade completes, order the window out and reset to home. The
        // token drops a stale completion if the panel was reopened meanwhile.
        transition += 1
        let token = transition
        withAnimation(Motion.close) { state.panelVisible = false }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Motion.closeDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.transition == token else { return }
                self.panel.orderOut(nil)
                self.state.selected = nil
            }
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        if panel.isVisible { close() }
    }

    // MARK: - menu-bar ring glyphs

    /// Two side-by-side rings: CPU (left) and memory (right).
    /// The two rings (CPU, memory) — with a small moon after them while sleep
    /// is being prevented, so it's visible without opening the panel. The moon
    /// is drawn in the bar's text color (resolved at draw time), like a
    /// template glyph, so it reads on any wallpaper.
    private func dualRingGlyph(cpuPct: Double, memPct: Double, awake: Bool) -> NSImage {
        let dim: CGFloat = 16, gap: CGFloat = 4, moon: CGFloat = 11
        let size = NSSize(width: dim * 2 + gap + (awake ? gap + moon : 0), height: dim)
        let pressure = state.memPressure
        let img = NSImage(size: size, flipped: false) { _ in
            self.drawRing(in: NSRect(x: 0, y: 0, width: dim, height: dim),
                          percent: cpuPct, color: NSColor(loadColor(cpuPct)))
            self.drawRing(in: NSRect(x: dim + gap, y: 0, width: dim, height: dim),
                          percent: memPct, color: NSColor(pressureColor(pressure)))
            if awake, let m = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: "Keeping awake")?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)
                    .applying(.init(paletteColors: [.labelColor]))) {
                m.draw(in: NSRect(x: dim * 2 + gap * 2, y: (dim - moon) / 2, width: moon, height: moon))
            }
            return true
        }
        img.isTemplate = false   // keep the ring colors
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
}
