import SwiftUI

let panelWidth: CGFloat = 300
let panelShape = RoundedRectangle(cornerRadius: 26, style: .continuous)

extension View {
    func innerCard(_ radius: CGFloat = 14, opacity: Double = 0.05) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(opacity)))
    }
}

/// Outer card with genuine macOS 26 Liquid Glass + soft shadow + startup fade.
struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        MenuContent()
            .frame(width: panelWidth)
            .glassEffect(.regular, in: panelShape)
            .shadow(color: .black.opacity(0.34), radius: 22, y: 12)
            .padding(GlassPanel.shadowPad)
            .environment(\.colorScheme, .dark)
            .tint(.blue)
            .opacity(state.panelVisible ? 1 : 0)
            .scaleEffect(state.panelVisible ? 1 : 0.96, anchor: .top)
            .fixedSize()
    }
}

/// Full-width Liquid Glass action button; prominent blue when active.
struct ActionButton: View {
    let title: String
    let systemImage: String
    var active: Bool = false
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.large)
        .tint(.blue)

        if active {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }
}
