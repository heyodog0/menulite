import AppKit
import SwiftUI

/// Borderless, transparent panel hosting the SwiftUI UI. The rounded glass card
/// and its shadow are drawn in SwiftUI; the window itself is invisible.
final class GlassPanel: NSPanel {
    /// Transparent inset around the card so the SwiftUI drop-shadow isn't clipped.
    static let shadowPad: CGFloat = 14

    init<Content: View>(content: Content) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 320),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                 // shadow is drawn in SwiftUI
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingController(rootView: AnyView(content))
        host.sizingOptions = [.preferredContentSize]
        contentViewController = host
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func forceLayout() {
        contentViewController?.view.layoutSubtreeIfNeeded()
    }
}
