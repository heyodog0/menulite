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
    @Published var memPressure: Int = 1     // 1 normal, 2 warning, 4 critical

    // Network throughput (bytes/sec)
    @Published var netDown: Double = 0
    @Published var netUp: Double = 0

    // Thermals (read straight from the SMC)
    @Published var cpuTemp: Double = 0      // °C, 0 = unavailable
    @Published var gpuTemp: Double = 0      // °C
    @Published var fanRPM: Double = 0
    @Published var fanMin: Double = 0
    @Published var fanMax: Double = 0
    @Published var fanCount: Int = 0

    // Rolling history for the graphs
    @Published var cpuHistory: [Double] = []   // %
    @Published var memHistory: [Double] = []   // bytes used
    @Published var diskHistory: [Double] = []  // % used
    @Published var netHistory: [Double] = []   // total bytes/sec
    let maxHistory = 90

    // Drill-in
    @Published var selected: Resource? = nil {
        // Keep showing the previous rows until fresh ones arrive (no empty flash).
        didSet {
            if selected != oldValue {
                confirmingPID = nil
                applyCachedHeight()   // size the body in lockstep with the cross-fade
                refreshProcesses()
            }
        }
    }
    @Published var processes: [ProcInfo] = []
    @Published var searchText: String = ""
    // Which row (PID) is showing its inline Quit / Force Quit confirm, and a
    // transient note shown when a kill is denied (e.g. root-owned process).
    @Published var confirmingPID: Int32? = nil
    @Published var killNote: String? = nil

    // Panel show/hide (drives the startup fade/scale).
    @Published var panelVisible = false

    /// Closes the panel. Set by StatusController; called from SwiftUI (tapping
    /// outside the glass) so the view layer can dismiss without knowing AppKit.
    var closePanel: (() -> Void)?

    // MARK: panel sizing
    //
    // The glass and all height animation live in SwiftUI (the window is a
    // transparent canvas). `screenHeight` is the natural height of the current
    // body (below the fixed rings) — SwiftUI animates the body's frame to it, so
    // the panel grows/shrinks smoothly with no AppKit frame animation (nothing to
    // slide or blink). `panelContentHeight` is the full glass height the window
    // must at least cover; the window snaps to it invisibly (transparent margin).

    /// Natural height of the current screen's body. SwiftUI animates to this.
    @Published var screenHeight: CGFloat = 0 { didSet { recomputePanelHeight() } }
    /// Measured height of the fixed chrome (the rings row). Constant in practice.
    @Published var chromeHeight: CGFloat = 0 { didSet { recomputePanelHeight() } }
    /// Full glass height (chrome + body + padding); drives the transparent window.
    @Published var panelContentHeight: CGFloat = 0

    // Outer padding (top 8 + bottom 14) + the VStack(spacing: 12) header↔body gap.
    private let panelVPadding: CGFloat = 34

    private func recomputePanelHeight() {
        let h = chromeHeight + screenHeight + panelVPadding
        if abs(h - panelContentHeight) > 0.5 { panelContentHeight = h }
    }

    /// Last measured body height per screen, so re-visiting one sizes immediately.
    private var cachedScreenHeights: [String: CGFloat] = [:]
    private var screenKey: String { selected?.rawValue ?? "home" }

    /// Called by the hidden probe with the current screen's natural body height.
    /// Applied instantly: it lands a frame *after* the content changed, so animating
    /// it would teleport. Smooth animation comes from applyCachedHeight on a known
    /// destination. (When it just confirms the cached value the guard makes it a
    /// no-op, so it never cuts a running animation short.)
    func reportScreenHeight(_ h: CGFloat) {
        guard h > 0 else { return }
        cachedScreenHeights[screenKey] = h
        guard abs(h - screenHeight) > 0.5 else { return }
        var tx = Transaction(); tx.disablesAnimations = true
        withTransaction(tx) { screenHeight = h }
    }

    /// On a screen change, jump the body height to the cached value (if known) so
    /// the SwiftUI height animation starts together with the content cross-fade.
    private func applyCachedHeight() {
        if let h = cachedScreenHeights[screenKey] { screenHeight = h }
    }

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
    private let thermal = ThermalMonitor()
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
        memPressure = stats.memoryPressure()

        sampleThermal()
        sampleNetwork()

        push(&cpuHistory, cpu)
        push(&memHistory, memUsed)
        push(&diskHistory, diskUsedPct)
        push(&netHistory, netDown + netUp)
    }

    /// Read the SMC off the main thread — it can sleep a few ms retrying flaky
    /// Apple Silicon sensors — then publish on main.
    private func sampleThermal() {
        let tm = thermal
        Task.detached(priority: .utility) {
            let t = tm.read()
            await MainActor.run {
                self.cpuTemp = t.cpuTemp; self.gpuTemp = t.gpuTemp
                self.fanRPM = t.fanRPM; self.fanMin = t.fanMin; self.fanMax = t.fanMax
                self.fanCount = t.fanCount
            }
        }
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

    /// Quit (SIGTERM) or force-quit (SIGKILL) a process, then refresh the list.
    /// Self and PID 1 are never targeted. A denied kill (root-owned process)
    /// surfaces a brief inline note rather than escalating to admin.
    func quit(_ proc: ProcInfo, force: Bool) {
        confirmingPID = nil
        let pid = proc.id
        guard pid > 1, pid != ProcessInfo.processInfo.processIdentifier else { return }

        let rc = Darwin.kill(pid, force ? SIGKILL : SIGTERM)
        if rc != 0 {
            switch errno {
            case EPERM: showKillNote("“\(proc.name)” needs admin to quit")
            case ESRCH: break   // already gone — the refresh will drop it
            default:    showKillNote("Couldn’t quit “\(proc.name)”")
            }
        }
        // Give the process a beat to exit before re-sampling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refreshProcesses()
        }
    }

    private var killNoteToken = 0
    private func showKillNote(_ text: String) {
        killNote = text
        killNoteToken += 1
        let token = killNoteToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.killNoteToken == token else { return }
            self.killNote = nil
        }
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

    /// Ring color: memory by pressure (calm blue normally), others by load.
    func tint(for r: Resource) -> Color {
        r == .memory ? pressureColor(memPressure) : loadColor(percent(for: r))
    }

    func toggleCleaning() {
        if cleaning { cleaner.stop(); cleaning = false }
        else { cleaning = cleaner.start() }
    }
}
