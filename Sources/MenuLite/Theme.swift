import SwiftUI
import AppKit

let panelWidth: CGFloat = 300
let panelShape = RoundedRectangle(cornerRadius: 26, style: .continuous)

/// Real backdrop-blur via NSVisualEffectView (more convincing than SwiftUI's
/// material alone). `.hudWindow` reads as dark glass.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        v.isEmphasized = true
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

/// Fakes Liquid Glass: backdrop blur + a top specular sheen + a bright top rim.
struct PanelGlass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(VisualEffectBlur().clipShape(panelShape))
            .background(panelShape.fill(Color.black.opacity(0.12)))
            .overlay(   // specular sheen catching light at the top
                panelShape
                    .fill(LinearGradient(
                        colors: [.white.opacity(0.14), .clear],
                        startPoint: .top, endPoint: .center))
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false))
            .overlay(   // bright rim, brighter at the top edge
                panelShape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.06)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.8))
    }
}

extension View {
    func innerCard(_ radius: CGFloat = 14, opacity: Double = 0.05) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(opacity)))
    }
}

/// Outer glass card + soft shadow + startup fade/scale. Flush under the bar.
struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        MenuContent()
            .frame(width: panelWidth)
            .modifier(PanelGlass())
            .clipShape(panelShape)
            .shadow(color: .black.opacity(0.42), radius: 22, y: 12)
            .padding(GlassPanel.shadowPad)
            .environment(\.colorScheme, .dark)
            .tint(.blue)
            .opacity(state.panelVisible ? 1 : 0)
            .scaleEffect(state.panelVisible ? 1 : 0.96, anchor: .top)
            .fixedSize()
    }
}

/// Full-width glassy action button; tints blue when active.
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
                shape.fill(LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.82)],
                    startPoint: .top, endPoint: .bottom))
            } else {
                shape.fill(.white.opacity(0.07))
            }
        }
        .overlay(shape.strokeBorder(.white.opacity(active ? 0.30 : 0.10), lineWidth: 0.8))
        .animation(.easeOut(duration: 0.2), value: active)
    }
}
