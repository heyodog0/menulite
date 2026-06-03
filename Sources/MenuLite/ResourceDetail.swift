import SwiftUI

/// Drill-in panel: segmented tabs, history graph, search, and the live
/// "what's eating it" process list.
struct ResourceDetail: View {
    @EnvironmentObject var state: AppState
    let resource: Resource

    private var binding: Binding<Resource> {
        Binding(get: { resource },
                set: { new in withAnimation(.snappy(duration: 0.28)) { state.selected = new } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { withAnimation(.snappy(duration: 0.28)) { state.selected = nil } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.borderless)
                SegmentedTabs(selection: binding)
            }

            HistoryChart(resource: resource, values: history)
                .padding(.vertical, 8).padding(.horizontal, 8)
                .innerCard(16, opacity: 0.05)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Search
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("Search process", text: $state.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !state.searchText.isEmpty {
                    Button { state.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Capsule().fill(.white.opacity(0.07)))

            // Process list — fixed height so switching tabs never resizes the panel.
            ScrollView {
                VStack(spacing: 2) {
                    if filtered.isEmpty {
                        Text(emptyText).font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                    } else {
                        ForEach(filtered) { p in
                            HStack {
                                Text(p.name).lineLimit(1).truncationMode(.tail)
                                    .font(.system(size: 12))
                                Spacer(minLength: 8)
                                Text(p.display)
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3).padding(.horizontal, 4)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: 152)
        }
    }

    private var history: [Double] {
        switch resource {
        case .cpu:    return state.cpuHistory
        case .memory: return state.memHistory
        case .disk:   return state.diskHistory
        }
    }

    private var filtered: [ProcInfo] {
        let q = state.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let rows = q.isEmpty ? state.processes
                             : state.processes.filter { $0.name.lowercased().contains(q) }
        return Array(rows.prefix(q.isEmpty ? 8 : 20))
    }

    private var emptyText: String {
        if !state.searchText.isEmpty { return "No matching process" }
        return resource == .disk ? "Measuring disk activity…" : "Reading processes…"
    }
}
