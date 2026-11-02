// © 2026 Ryan Truong. All rights reserved. Not licensed for copying, porting or
// reimplementation, by hand or with AI tools. See LICENSE.

import SwiftUI

/// Drill-in panel: icon tabs and a close button, the live value with its peak
/// and average, a smooth history chart (Disk: a capacity bar), then what's
/// using it — the process list, or download/upload for Network. Every tab is
/// the same height, so switching never resizes the panel.
struct ResourceDetail: View {
    @EnvironmentObject var state: AppState
    let resource: Resource
    /// What the content below the tabs is showing. On a tab switch it trails
    /// `resource` by a moment, so the slide's direction is set before the old
    /// page leaves: it slides out one way and the new one in from the other,
    /// like paging — nothing fades, so nothing blends or flashes.
    @State private var shown: Resource?
    @State private var forward = true
    private var shownResource: Resource { shown ?? resource }

    private var page: AnyTransition {
        .asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                    removal: .move(edge: forward ? .leading : .trailing))
    }
    /// The search field takes focus only when clicked, so opening a tab
    /// doesn't park a blinking cursor in it.
    @FocusState private var searching: Bool

    private var binding: Binding<Resource> {
        Binding(get: { resource },
                set: { new in withAnimation(Motion.screen) { state.selected = new } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SegmentedTabs(selection: binding)
                Button { withAnimation(Motion.screen) { state.selected = nil } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Back")
            }

            ZStack(alignment: .top) {
                content.id(shownResource).transition(page)
            }
        }
        .onChange(of: resource) { old, new in switchContent(from: old, to: new) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Group {
                if shownResource == .disk {
                    capacityCard
                } else {
                    // One color on every tab: the rings already say how
                    // loaded each one is.
                    HistoryChart(resource: shownResource, values: history)
                }
            }
            .padding(.vertical, 10).padding(.horizontal, 10)
            .frame(height: chartCardHeight)
            .innerCard(14, opacity: 0.05)

            if shownResource == .network { networkBody } else { processBody }
        }
    }

    /// Point the slide toward the new tab, then page to it.
    private func switchContent(from old: Resource, to new: Resource) {
        let order = Resource.allCases
        forward = (order.firstIndex(of: new) ?? 0) > (order.firstIndex(of: old) ?? 0)
        DispatchQueue.main.async { withAnimation(Motion.screen) { shown = new } }
    }

    private let chartCardHeight: CGFloat = 104

    // MARK: header — the live number, and its peak / average over the chart

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(shownResource.tabTitle.uppercased())
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.system(size: 22, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(sideStats, id: \.0) { label, v in
                    HStack(spacing: 4) {
                        Text(label).foregroundStyle(.tertiary)
                        Text(v).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.system(size: 10, weight: .medium))
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private var value: String {
        switch shownResource {
        case .cpu:     return "\(Int(state.cpu.rounded()))%"
        case .memory:  return gb(state.memUsed, digits: 1)
        case .network: return fmtRate(state.netDown + state.netUp)
        case .disk:    return "\(Int(state.diskUsedPct.rounded()))%"
        }
    }

    private var detail: String {
        switch shownResource {
        case .cpu:     return "\(ProcessInfo.processInfo.activeProcessorCount) cores"
        case .memory:  return "of \(gb(state.memTotal, digits: 0))"
        case .network: return "total"
        case .disk:    return "used"
        }
    }

    private var sideStats: [(String, String)] {
        let h = history
        guard shownResource != .disk else { return [] }   // the capacity card has it all
        guard !h.isEmpty else { return [] }
        let peak = h.max() ?? 0, avg = h.reduce(0, +) / Double(h.count)
        let f: (Double) -> String = { v in
            switch shownResource {
            case .memory:  return gb(v, digits: 1)
            case .network: return fmtRate(v)
            default:       return "\(Int(v.rounded()))%"
            }
        }
        var out = [("Peak", f(peak)), ("Avg", f(avg))]
        if shownResource == .memory { out.append(("Pressure", pressureName)) }
        return out
    }

    private var pressureName: String {
        switch state.memPressure {
        case 4:  return "Critical"
        case 2:  return "Elevated"
        default: return "Normal"
        }
    }

    private func gb(_ bytes: Double, digits: Int) -> String {
        String(format: "%.\(digits)f GB", bytes / 1e9)
    }

    // MARK: disk — capacity bar in the chart's place

    private var capacityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(pillFill(state.tint(for: .disk)))
                        .frame(width: max(8, geo.size.width * state.diskUsedPct / 100))
                }
            }
            .frame(height: 12)
            HStack {
                capStat("Used", gb(state.diskTotal - state.diskFree, digits: 1), state.tint(for: .disk))
                Spacer()
                capStat("Free", gb(state.diskFree, digits: 1), .white.opacity(0.35))
                Spacer()
                capStat("Total", gb(state.diskTotal, digits: 0), nil)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private func capStat(_ label: String, _ value: String, _ dot: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
                Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text(value).font(.system(size: 13, weight: .semibold).monospacedDigit())
        }
    }

    // MARK: network — download/upload now, peaks, and totals since launch

    private var networkBody: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                rateTile("arrow.down", "Download", state.netDown, state.netDownHistory.max() ?? 0, .blue)
                rateTile("arrow.up", "Upload", state.netUp, state.netUpHistory.max() ?? 0, .green)
            }
            HStack {
                Text("Since launch").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Label(fmtBytes(state.netSessionDown), systemImage: "arrow.down")
                Label(fmtBytes(state.netSessionUp), systemImage: "arrow.up")
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .padding(.horizontal, 12).padding(.vertical, 9)
            .innerCard(12, opacity: 0.05)
            Spacer(minLength: 0)
        }
        .frame(height: detailBodyHeight, alignment: .top)
    }

    private func rateTile(_ icon: String, _ title: String, _ bps: Double, _ peak: Double,
                          _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
            Text(fmtRate(bps)).font(.system(size: 16, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText())
            Text("peak \(fmtRate(peak))").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 9)
        .innerCard(12, opacity: 0.05)
    }

    // MARK: cpu / memory / disk — searchable process list

    private var processBody: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                TextField(shownResource.processHeading, text: $state.searchText)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .focused($searching)
                    .onAppear { DispatchQueue.main.async { searching = false } }
                if !state.searchText.isEmpty {
                    Button { state.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.06)))

            if let note = state.note {
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
                        let top = filtered.map(\.value).max() ?? 1
                        ForEach(filtered) { p in
                            ProcRow(proc: p, share: top > 0 ? p.value / top : 0,
                                    tint: .accentColor)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .scrollEdges()
            .frame(height: processListHeight + 8)
        }
        .frame(height: detailBodyHeight, alignment: .top)
        .animation(.snappy(duration: 0.2), value: state.note)
        .animation(.snappy(duration: 0.2), value: state.confirmingPID)
    }

    private var history: [Double] {
        switch shownResource {
        case .cpu:     return state.cpuHistory
        case .memory:  return state.memHistory
        case .disk:    return state.diskHistory
        case .network: return state.netHistory
        }
    }

    private var filtered: [ProcInfo] {
        let q = state.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let all = state.processCache[shownResource] ?? []
        let rows = q.isEmpty ? all : all.filter { $0.name.lowercased().contains(q) }
        return Array(rows.prefix(q.isEmpty ? 10 : 20))
    }

    private var emptyText: String {
        if !state.searchText.isEmpty { return "No matching process" }
        return shownResource == .disk ? "Measuring disk activity…" : "Reading processes…"
    }
}

/// One process row. Hovering reveals an ✕ that expands the row into an inline
/// Quit / Force Quit confirm (no modal — a modal would steal key focus and
/// dismiss the whole panel). Tap ✕ again, or the name, to cancel.
private struct ProcRow: View {
    @EnvironmentObject var state: AppState
    let proc: ProcInfo
    /// This row's value relative to the top row, drawn as a faint bar behind it.
    let share: Double
    let tint: Color
    @State private var hovering = false

    private var confirming: Bool { state.confirmingPID == proc.id }

    var body: some View {
        HStack(spacing: 7) {
            ProcIcon(pid: proc.id, name: proc.name)
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
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
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
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(confirming ? 0 : 0.10))
                    .frame(width: max(4, geo.size.width * min(1, share)))
                    .animation(.easeOut(duration: 0.3), value: share)   // the bar glides; text doesn't
            }
        }
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(.white.opacity(confirming ? 0.07 : (hovering ? 0.05 : 0))))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// The process's app icon — its own, or for a helper ("Google Chrome Helper
/// (Renderer)") its app's — else a quiet gear for daemons. Cached per pid.
private struct ProcIcon: View {
    let pid: Int32
    let name: String

    @MainActor private static var cache: [Int32: NSImage?] = [:]

    private var icon: NSImage? {
        if let hit = Self.cache[pid] { return hit }
        var img = NSRunningApplication(processIdentifier: pid)?.icon
        if img == nil, let r = name.range(of: " Helper") {
            let app = String(name[..<r.lowerBound])
            img = NSWorkspace.shared.runningApplications.first { $0.localizedName == app }?.icon
        }
        Self.cache[pid] = img
        return img
    }

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.white.opacity(0.08)))
            }
        }
        .frame(width: 16, height: 16)
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
