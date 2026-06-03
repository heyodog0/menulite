import SwiftUI
import Combine

/// Central observable state. Owns the four feature managers and a poll timer.
@MainActor
final class AppState: ObservableObject {
    // Live system stats
    @Published var cpu: Double = 0          // percent 0…100
    @Published var memUsed: Double = 0      // bytes
    @Published var memTotal: Double = 1
    @Published var diskFree: Double = 0     // bytes
    @Published var diskTotal: Double = 1

    // Rolling history for the graphs
    @Published var cpuHistory: [Double] = []   // %
    @Published var memHistory: [Double] = []   // bytes used
    @Published var diskHistory: [Double] = []  // % used
    let maxHistory = 90

    // Drill-in
    @Published var selected: Resource? = nil {
        didSet { processes = []; refreshProcesses() }
    }
    @Published var processes: [ProcInfo] = []

    // Toggles
    @Published var preventSleep = false {
        didSet { sleepManager.setEnabled(preventSleep) }
    }
    @Published var dimLevel: Double = 0 {
        didSet { dimmer.setDim(dimLevel) }
    }
    @Published var cleaning = false

    private let sleepManager = SleepManager()
    private let stats = StatsMonitor()
    private let dimmer = DisplayDimmer()
    private let procSampler = ProcessSampler()
    private lazy var cleaner = KeyboardCleaner { [weak self] in
        self?.cleaning = false
    }

    private var timer: Timer?

    init() {
        sample()
        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 0.5
        timer = t
    }

    private func tick() {
        sample()
        if selected != nil { refreshProcesses() }
    }

    private func sample() {
        cpu = stats.cpuUsage()
        let m = stats.memory()
        memUsed = m.used; memTotal = m.total
        let d = stats.disk()
        diskFree = d.free; diskTotal = d.total

        push(&cpuHistory, cpu)
        push(&memHistory, memUsed)
        push(&diskHistory, diskUsedPct)
    }

    private func push(_ arr: inout [Double], _ v: Double) {
        arr.append(v)
        if arr.count > maxHistory { arr.removeFirst(arr.count - maxHistory) }
    }

    private func refreshProcesses() {
        guard let res = selected else { return }
        let sampler = procSampler
        Task.detached(priority: .utility) {
            let rows = sampler.top(for: res)
            await MainActor.run {
                // Ignore if the user switched panels meanwhile.
                if self.selected == res { self.processes = rows }
            }
        }
    }

    // MARK: derived display helpers
    var memPct: Double { memTotal > 0 ? memUsed / memTotal * 100 : 0 }
    var diskUsedPct: Double { diskTotal > 0 ? (diskTotal - diskFree) / diskTotal * 100 : 0 }

    func fraction(for r: Resource) -> Double {
        switch r {
        case .cpu:    return cpu / 100
        case .memory: return memPct / 100
        case .disk:   return diskUsedPct / 100
        }
    }
    func percent(for r: Resource) -> Double {
        switch r {
        case .cpu:    return cpu
        case .memory: return memPct
        case .disk:   return diskUsedPct
        }
    }

    var menuBarLabel: String { String(format: "C%.0f M%.0f", cpu, memPct) }

    func toggleCleaning() {
        if cleaning { cleaner.stop(); cleaning = false }
        else { cleaning = cleaner.start() }
    }
}
