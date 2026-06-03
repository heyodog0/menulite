import AppKit
import SwiftUI

/// Borderless panel whose background is an AppKit Liquid Glass view
/// (NSGlassEffectView). The glass resizes natively with the window, so we get
/// real Liquid Glass AND a smooth home/detail resize — something SwiftUI's
/// glassEffect can't do (it recurses/crashes when its area resizes).
final class GlassPanel: NSPanel {
    static let cornerRadius: CGFloat = 26

    init<Content: View>(content: Content) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 340),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let glass = NSGlassEffectView()
        glass.cornerRadius = Self.cornerRadius

        let host = NSHostingView(rootView: AnyView(content))
        host.frame = glass.bounds
        host.autoresizingMask = [.width, .height]
        host.layer?.backgroundColor = .clear
        glass.contentView = host

        contentView = glass
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
