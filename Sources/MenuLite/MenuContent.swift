import SwiftUI

struct MenuContent: View {
    @EnvironmentObject var state: AppState

    private let glassShape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    var body: some View {
        VStack(spacing: 12) {
            // Fixed header: the three tappable dials, always visible. Measured as
            // chrome so it sits outside the height-animated body and can never be
            // clipped or briefly overlaid during a home↔detail transition.
            HStack(spacing: 4) {
                ForEach(Resource.ringCases) { r in
                    Button {
                        withAnimation(.snappy(duration: 0.3)) {
                            state.selected = (state.selected == r) ? nil : r
                        }
                    } label: {
                        RingGauge(resource: r,
                                  fraction: state.fraction(for: r),
                                  percent: state.percent(for: r),
                                  tint: state.tint(for: r),
                                  selected: state.selected == r,
                                  animated: state.panelVisible)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
                state.chromeHeight = $0
            }

            bodyArea
        }
        .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 8)
        .frame(width: panelWidth, alignment: .top)
        // The glass — native NSGlassEffectView behind the content, hugging it and
        // animating its height with the body (all in SwiftUI; the window is clear).
        .background(GlassBackground().clipShape(glassShape))
        .overlay(glassShape.strokeBorder(.white.opacity(0.10), lineWidth: 0.8))
        .clipShape(glassShape)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// The body below the rings: the active screen, cross-fading + scaling from the
    /// top, with its frame height animated to the current screen's natural height
    /// (measured by the hidden probe). Clipped so the outgoing screen doesn't spill
    /// while shorter — and the clip excludes the header (rings) above.
    private var bodyArea: some View {
        ZStack(alignment: .top) { activeScreen }
            .animation(.snappy(duration: 0.3), value: state.selected)
            .frame(height: state.screenHeight > 0 ? state.screenHeight : nil, alignment: .top)
            .clipped()
            .animation(.snappy(duration: 0.3), value: state.screenHeight)
            // Hidden, instantly-swapping copy reports the current screen's natural
            // height (no cross-fade union), without affecting layout.
            .background(alignment: .top) {
                ZStack(alignment: .top) { activeScreen }
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
                        state.reportScreenHeight($0)
                    }
            }
    }

    /// The screen for the current selection. Used twice — once visible (cross-faded
    /// + scaled) and once hidden to measure its natural height.
    @ViewBuilder
    private var activeScreen: some View {
        let move = AnyTransition.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
            removal: .opacity.animation(.easeOut(duration: 0.12)))
        if let r = state.selected {
            ResourceDetail(resource: r).transition(move)
        } else {
            Controls().transition(move)
        }
    }
}

/// Default panel: prevent-sleep + clean-keyboard buttons, brightness slider, quit.
private struct Controls: View {
    @EnvironmentObject var state: AppState

    private var brightness: Binding<Double> {
        Binding(get: { 1 - state.dimLevel / 0.9 },
                set: { state.dimLevel = (1 - $0) * 0.9 })
    }

    var body: some View {
        VStack(spacing: 12) {
            SensorsStrip()

            ActionButton(title: state.preventSleep ? "Sleep prevented" : "Prevent sleep",
                         systemImage: "moon.zzz.fill", active: state.preventSleep) {
                state.preventSleep.toggle()
            }
            ActionButton(title: state.cleaning ? "Stop cleaning" : "Clean keyboard",
                         systemImage: "keyboard", active: state.cleaning) {
                state.toggleCleaning()
            }

            Divider().opacity(0.4).padding(.vertical, 2)

            VStack(spacing: 8) {
                Text("External Monitor Brightness")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                HStack(spacing: 9) {
                    Image(systemName: "moon.fill").font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Slider(value: brightness, in: 0...1)
                    Image(systemName: "sun.max.fill").font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
