import AppKit

/// Dims external displays with a translucent, click-through black overlay
/// window per external screen. Works on any monitor (no DDC needed).
@MainActor
final class DisplayDimmer {
    private var windows: [NSWindow] = []
    private var level: Double = 0

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func setDim(_ newLevel: Double) {
        level = min(max(newLevel, 0), 0.9)
        apply()
    }

    @objc private func screensChanged() { rebuild() }

    private func externalScreens() -> [NSScreen] {
        NSScreen.screens.filter { screen in
            guard let n = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(CGDirectDisplayID(n.uint32Value)) == 0
        }
    }

    /// Apply the current level without churn: when the overlay windows already
    /// match the screen layout, just update their alpha (smooth while dragging
    /// the slider). Only tear down / recreate when crossing the on-off boundary
    /// or when the screen count changed.
    private func apply() {
        guard level > 0.001 else {
            teardown()
            return
        }
        if windows.count == externalScreens().count {
            for w in windows { w.alphaValue = CGFloat(level) }
        } else {
            rebuild()
        }
    }

    private func teardown() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func rebuild() {
        // Tear down and recreate to match the current external-screen layout.
        teardown()

        guard level > 0.001 else { return }

        for screen in externalScreens() {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                             backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .black
            w.alphaValue = CGFloat(level)
            w.level = .screenSaver
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append(w)
        }
    }
}
