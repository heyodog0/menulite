import SwiftUI

/// Always-visible thermal readout on the home panel: CPU temp, GPU temp, and fan
/// RPM, read straight from the SMC. Values update with the 2s sample tick.
struct SensorsStrip: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            tile(icon: "cpu.fill", value: tempText(state.cpuTemp),
                 label: "CPU", tint: tempColor(state.cpuTemp))
            tile(icon: "cpu", value: tempText(state.gpuTemp),
                 label: "GPU", tint: tempColor(state.gpuTemp))
            tile(icon: "fanblades.fill", value: fanText,
                 label: fanLabel, tint: fanColor)
        }
    }

    private func tile(icon: String, value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(tint)
                Text(value).font(.system(size: 14, weight: .semibold).monospacedDigit())
            }
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .innerCard(12, opacity: 0.05)
    }

    // MARK: temps

    private func tempText(_ c: Double) -> String {
        c > 0 ? "\(Int(c.rounded()))°" : "—"
    }

    // Apple Silicon runs warm by design; keep green generous, only flag real heat.
    private func tempColor(_ c: Double) -> Color {
        switch c {
        case ..<1:   return .secondary   // unavailable
        case ..<70:  return .green
        case ..<90:  return .orange
        default:     return .red
        }
    }

    // MARK: fan

    // "—" only when the SMC has no fan (unreadable). A genuine 0 rpm means the
    // fan is off — normal on Apple Silicon when cool — so show "Off", not "—".
    private var fanText: String {
        guard state.fanCount > 0 else { return "—" }
        return state.fanRPM > 0 ? "\(Int(state.fanRPM.rounded()))" : "Off"
    }

    // Show how hard the fan is working relative to its own min/max range.
    private var fanLabel: String {
        guard state.fanCount > 0 else { return "no sensor" }
        guard state.fanRPM > 0 else { return "fan · silent" }
        guard state.fanMax > state.fanMin else { return "rpm" }
        let span = state.fanMax - state.fanMin
        let frac = max(0, (state.fanRPM - state.fanMin) / span)
        switch frac {
        case ..<0.08: return "min · rpm"
        case ..<0.5:  return "low · rpm"
        case ..<0.85: return "ramped · rpm"
        default:      return "max · rpm"
        }
    }

    private var fanColor: Color {
        guard state.fanCount > 0, state.fanRPM > 0, state.fanMax > state.fanMin else {
            return .secondary
        }
        let frac = (state.fanRPM - state.fanMin) / (state.fanMax - state.fanMin)
        return frac < 0.5 ? .blue : (frac < 0.85 ? .orange : .red)
    }
}
