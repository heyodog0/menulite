import SwiftUI

/// Drill-in panel: history graph + live "what's eating it" process list.
struct ResourceDetail: View {
    @EnvironmentObject var state: AppState
    let resource: Resource

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button {
                    state.selected = nil
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                Text(resource.rawValue).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(String(format: "%.0f%%", state.percent(for: resource)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(loadColor(state.percent(for: resource)))
            }

            HistoryChart(resource: resource, values: history,
                         color: loadColor(state.percent(for: resource)))

            Text(resource.processHeading)
                .font(.caption).foregroundStyle(.secondary)

            if state.processes.isEmpty {
                Text(resource == .disk ? "Measuring disk activity…" : "Reading processes…")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach(state.processes) { p in
                    HStack {
                        Text(p.name).lineLimit(1).truncationMode(.tail)
                            .font(.system(size: 12))
                        Spacer(minLength: 8)
                        Text(p.display)
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var history: [Double] {
        switch resource {
        case .cpu:    return state.cpuHistory
        case .memory: return state.memHistory
        case .disk:   return state.diskHistory
        }
    }
}
