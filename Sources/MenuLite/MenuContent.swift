import SwiftUI

struct MenuContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 14) {
            // Three tappable dials.
            HStack(spacing: 10) {
                ForEach(Resource.allCases) { r in
                    Button {
                        state.selected = (state.selected == r) ? nil : r
                    } label: {
                        RingGauge(resource: r,
                                  fraction: state.fraction(for: r),
                                  percent: state.percent(for: r),
                                  selected: state.selected == r)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            if let r = state.selected {
                ResourceDetail(resource: r)
            } else {
                Controls()
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}

/// Default panel: the toggles + slider + actions.
private struct Controls: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Prevent sleep", isOn: $state.preventSleep)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Dim external")
                    Spacer()
                    Text(state.dimLevel < 0.01 ? "off"
                         : String(format: "%.0f%%", state.dimLevel / 0.9 * 100))
                        .foregroundStyle(.secondary).font(.caption.monospacedDigit())
                }
                Slider(value: $state.dimLevel, in: 0...0.9)
            }

            Button {
                state.toggleCleaning()
            } label: {
                Label(state.cleaning ? "Stop cleaning" : "Clean keyboard",
                      systemImage: "keyboard")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Divider()

            Button("Quit MenuLite") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }
}
