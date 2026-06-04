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

        // A layer-masked container clips the glass's rectangular backing to the
        // rounded shape — otherwise the glass's opaque corner pixels show as
        // black squares behind the rounded corners.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 340))
        container.wantsLayer = true
        container.layer?.cornerRadius = Self.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        let glass = NSGlassEffectView()
        glass.frame = container.bounds
        glass.autoresizingMask = [.width, .height]
        glass.cornerRadius = Self.cornerRadius

        let host = NSHostingView(rootView: AnyView(content))
        host.frame = glass.bounds
        host.autoresizingMask = [.width, .height]
        host.layer?.backgroundColor = .clear
        glass.contentView = host

        container.addSubview(glass)
        contentView = container
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
