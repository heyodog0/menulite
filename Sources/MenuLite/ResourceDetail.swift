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

            if resource == .disk {
                diskBody
            } else {
                HistoryChart(resource: resource, values: history)
                    .padding(.vertical, 12).padding(.horizontal, 10)
                    .innerCard(16, opacity: 0.05)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if resource == .network { networkBody } else { processBody }
            }
        }
    }

    // MARK: disk — capacity ring + breakdown (not activity)
    private var diskBody: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 16) {
                DiskRing(percent: state.diskUsedPct)
                    .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 14) {
                    capStat("Total Capacity", gb(state.diskTotal))
                    capStat("Used Space", gb(state.diskTotal - state.diskFree))
                    capStat("Free Space", gb(state.diskFree))
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        // Concrete height (the panel now hugs its content, so there's no fixed
        // window to stretch into); matches the network/process detail heights.
        .frame(height: 187)
    }

    private func capStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .semibold).monospacedDigit())
        }
    }

    private func gb(_ bytes: Double) -> String { String(format: "%.1f GB", bytes / 1e9) }

    // MARK: network — down/up rates instead of a process list
    private var networkBody: some View {
        VStack(spacing: 10) {
            rateRow("arrow.down", "Download", state.netDown, .blue)
            rateRow("arrow.up", "Upload", state.netUp, .green)
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .frame(height: 187, alignment: .top)   // matches the process-body height
    }

    private func rateRow(_ icon: String, _ title: String, _ bps: Double, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint).frame(width: 18)
            Text(title).font(.system(size: 13))
            Spacer()
            Text(fmtRate(bps)).font(.system(size: 14, weight: .semibold).monospacedDigit())
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .innerCard(12, opacity: 0.05)
    }

    // MARK: cpu / memory / disk — searchable process list
    private var processBody: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("Search process", text: $state.searchText)
                    .textFieldStyle(.plain).font(.system(size: 12))
                if !state.searchText.isEmpty {
                    Button { state.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Capsule().fill(.white.opacity(0.07)))

            if let note = state.killNote {
                Text(note).font(.system(size: 11)).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            ScrollView {
                VStack(spacing: 2) {
                    if filtered.isEmpty {
                        Text(emptyText).font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                    } else {
                        ForEach(filtered) { p in ProcRow(proc: p) }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: 144)
        }
        .animation(.snappy(duration: 0.2), value: state.killNote)
        .animation(.snappy(duration: 0.2), value: state.confirmingPID)
    }

    private var history: [Double] {
        switch resource {
        case .cpu:     return state.cpuHistory
        case .memory:  return state.memHistory
        case .disk:    return state.diskHistory
        case .network: return state.netHistory
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

/// One process row. Hovering reveals an ✕ that expands the row into an inline
/// Quit / Force Quit confirm (no modal — a modal would steal key focus and
/// dismiss the whole panel). Tap ✕ again, or the name, to cancel.
private struct ProcRow: View {
    @EnvironmentObject var state: AppState
    let proc: ProcInfo
    @State private var hovering = false

    private var confirming: Bool { state.confirmingPID == proc.id }

    var body: some View {
        HStack(spacing: 6) {
            Text(proc.name).lineLimit(1).truncationMode(.tail)
                .font(.system(size: 12))

            Spacer(minLength: 8)

            if confirming {
                Button("Quit")  { state.quit(proc, force: false) }
                    .buttonStyle(InlineKillButton(tint: .orange))
                Button("Force") { state.quit(proc, force: true) }
                    .buttonStyle(InlineKillButton(tint: .red))
            } else {
                Text(proc.display)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if hovering || confirming {
                Button {
                    state.confirmingPID = confirming ? nil : proc.id
                } label: {
                    Image(systemName: confirming ? "xmark.circle.fill" : "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(confirming ? .secondary : Color.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .help(confirming ? "Cancel" : "Quit process")
            }
        }
        .padding(.vertical, 3).padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(confirming ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct InlineKillButton: ButtonStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.28 : 0.16)))
    }
}
