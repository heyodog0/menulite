import SwiftUI

struct MenuContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 12) {
            // Three tappable dials, always visible.
            HStack(spacing: 6) {
                ForEach(Resource.allCases) { r in
                    Button {
                        withAnimation(.snappy(duration: 0.3)) {
                            state.selected = (state.selected == r) ? nil : r
                        }
                    } label: {
                        RingGauge(resource: r,
                                  fraction: state.fraction(for: r),
                                  percent: state.percent(for: r),
                                  selected: state.selected == r)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)

            // Swap between controls (home) and the resource detail.
            ZStack {
                if let r = state.selected {
                    ResourceDetail(resource: r)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity))
                } else {
                    Controls()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .leading)),
                            removal: .opacity))
                }
            }
        }
        .padding(14)
    }
}

/// Default panel: the toggles + slider + actions, in a soft card.
private struct Controls: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Prevent sleep", isOn: $state.preventSleep)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Dim external")
                    Spacer()
                    Text(state.dimLevel < 0.01 ? "off"
                         : String(format: "%.0f%%", state.dimLevel / 0.9 * 100))
                        .foregroundStyle(.secondary).font(.caption.monospacedDigit())
                }
                Slider(value: $state.dimLevel, in: 0...0.9)
            }

            Button { state.toggleCleaning() } label: {
                Label(state.cleaning ? "Stop cleaning" : "Clean keyboard",
                      systemImage: "keyboard")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            HStack {
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless).font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(14)
        .innerCard(16)
    }
}
