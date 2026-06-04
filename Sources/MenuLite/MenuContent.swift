import SwiftUI

struct MenuContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 12) {
            // Three tappable dials, always visible.
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
                                  selected: state.selected == r)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)

            ZStack {
                if let r = state.selected {
                    ResourceDetail(resource: r)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                } else {
                    Controls()
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
        }
        .padding(14)
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
