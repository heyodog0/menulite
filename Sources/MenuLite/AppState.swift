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

    // Network throughput (bytes/sec)
    @Published var netDown: Double = 0
    @Published var netUp: Double = 0

    // Rolling history for the graphs
    @Published var cpuHistory: [Double] = []   // %
    @Published var memHistory: [Double] = []   // bytes used
    @Published var diskHistory: [Double] = []  // % used
    @Published var netHistory: [Double] = []   // total bytes/sec
    let maxHistory = 90

    // Drill-in
    @Published var selected: Resource? = nil {
        // Keep showing the previous rows until fresh ones arrive (no empty flash).
        didSet { if selected != oldValue { refreshProcesses() } }
    }
    @Published var processes: [ProcInfo] = []
    @Published var searchText: String = ""

    // Panel show/hide (drives the startup fade/scale).
    @Published var panelVisible = false

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
    private let netMonitor = NetworkMonitor()
    private var prevNet: (down: UInt64, up: UInt64)?
    private var prevNetTime: Date?
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

        sampleNetwork()

        push(&cpuHistory, cpu)
        push(&memHistory, memUsed)
        push(&diskHistory, diskUsedPct)
        push(&netHistory, netDown + netUp)
    }

    private func sampleNetwork() {
        let n = netMonitor.sample()
        let now = Date()
        if let prev = prevNet, let pt = prevNetTime {
            let dt = now.timeIntervalSince(pt)
            if dt > 0 {
                netDown = n.down >= prev.down ? Double(n.down - prev.down) / dt : 0
                netUp   = n.up   >= prev.up   ? Double(n.up   - prev.up)   / dt : 0
            }
        }
        prevNet = n; prevNetTime = now
    }

    private func push(_ arr: inout [Double], _ v: Double) {
        arr.append(v)
        if arr.count > maxHistory { arr.removeFirst(arr.count - maxHistory) }
    }

    private func refreshProcesses() {
        guard let res = selected else { return }
        let sampler = procSampler
        Task.detached(priority: .utility) {
            let rows = sampler.top(for: res, limit: 40)
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
        case .cpu:     return cpu / 100
        case .memory:  return memPct / 100
        case .disk:    return diskUsedPct / 100
        case .network: return 0
        }
    }
    func percent(for r: Resource) -> Double {
        switch r {
        case .cpu:     return cpu
        case .memory:  return memPct
        case .disk:    return diskUsedPct
        case .network: return 0
        }
    }

    func toggleCleaning() {
        if cleaning { cleaner.stop(); cleaning = false }
        else { cleaning = cleaner.start() }
    }
}
