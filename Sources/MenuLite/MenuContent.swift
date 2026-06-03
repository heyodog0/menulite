import SwiftUI

struct MenuContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("System")
                .font(.caption).foregroundStyle(.secondary)

            StatRow(label: "CPU", pct: state.cpu,
                    detail: String(format: "%.0f%%", state.cpu))
            StatRow(label: "Memory", pct: state.memPct,
                    detail: "\(bytes(state.memUsed)) / \(bytes(state.memTotal))")
            StatRow(label: "Disk", pct: state.diskUsedPct,
                    detail: "\(bytes(state.diskFree)) free")

            Divider()

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
        .padding(14)
        .frame(width: 260)
    }

    private func bytes(_ n: Double) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowedUnits = [.useGB]
        return f.string(fromByteCount: Int64(n))
    }
}

private struct StatRow: View {
    let label: String
    let pct: Double
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(detail).font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(pct, 0), 100), total: 100)
                .tint(color)
        }
    }

    private var color: Color {
        switch pct {
        case ..<60:  return .green
        case ..<85:  return .orange
        default:     return .red
        }
    }
}
