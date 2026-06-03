import SwiftUI

let panelWidth: CGFloat = 320
let panelShape = RoundedRectangle(cornerRadius: 24, style: .continuous)
let cardShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

/// The outer glass card + soft shadow that sits flush under the menu bar.
struct RootView: View {
    var body: some View {
        MenuContent()
            .frame(width: panelWidth)
            .background {
                ZStack {
                    panelShape.fill(.ultraThinMaterial)
                    panelShape.fill(Color.black.opacity(0.22))   // deepen to dark glass
                }
            }
            .overlay(panelShape.strokeBorder(.white.opacity(0.10), lineWidth: 1))
            .clipShape(panelShape)
            .shadow(color: .black.opacity(0.40), radius: 18, y: 9)
            .padding(GlassPanel.shadowPad)
            .environment(\.colorScheme, .dark)   // match the dark reference look
            .tint(.blue)
            .fixedSize()
    }
}

/// A subtle translucent inner card (for grouping sections).
extension View {
    func innerCard(_ radius: CGFloat = 14, opacity: Double = 0.06) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.white.opacity(opacity))
        )
    }
}
