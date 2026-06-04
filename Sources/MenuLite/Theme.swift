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
/// The GlassEffectContainer provides the rendering context glassEffect needs;
/// inner controls are NOT glass (avoid glass-on-glass, which recurses/crashes).
/// Transparent SwiftUI content; the Liquid Glass + resize live in AppKit
/// (NSGlassEffectView), which is the one place glass can resize without
/// SwiftUI's glassEffect recursing.
struct RootView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        MenuContent()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
            .tint(.blue)
            .opacity(state.panelVisible ? 1 : 0)
            .scaleEffect(state.panelVisible ? 1 : 0.90, anchor: .top)
    }
}

/// Full-width action button; tints blue when active. (Plain control on the
/// glass panel — not itself glass.)
struct ActionButton: View {
    let title: String
    let systemImage: String
    var active: Bool = false
    let action: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9).padding(.horizontal, 12)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? .white : .primary)
        .background {
            if active {
                shape.fill(LinearGradient(colors: [.blue, .blue.opacity(0.82)],
                                          startPoint: .top, endPoint: .bottom))
            } else {
                shape.fill(.white.opacity(0.08))
            }
        }
        .overlay(shape.strokeBorder(.white.opacity(active ? 0.30 : 0.12), lineWidth: 0.8))
        .animation(.easeOut(duration: 0.2), value: active)
    }
}
