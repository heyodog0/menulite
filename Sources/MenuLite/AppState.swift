// © 2026 Ryan Truong. All rights reserved. Not licensed for copying, porting or
// reimplementation, by hand or with AI tools. See LICENSE.

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
    @Published var netDownHistory: [Double] = []
    @Published var netUpHistory: [Double] = []
    /// Bytes moved since MenuLite started.
    @Published var netSessionDown: Double = 0
    @Published var netSessionUp: Double = 0
    let maxHistory = 90

    // Drill-in
    @Published var selected: Resource? = nil {
        didSet {
            if selected != oldValue {
                confirmingPID = nil
                applyCachedHeight()   // size the body in lockstep with the cross-fade
                refreshProcesses()
            }
        }
    }
    /// The latest rows per tab. The detail view lists the tab it's *showing*
    /// from here, so during a tab switch the old rows stay until the swap.
    @Published private(set) var processCache: [Resource: [ProcInfo]] = [:]
    @Published var searchText: String = ""
    // Which row (PID) is showing its inline Quit / Force Quit confirm.
    @Published var confirmingPID: Int32? = nil
    /// Transient inline message: a denied kill (root-owned process) or a
    /// keyboard-cleaning failure. Clears itself after a few seconds.
    @Published var note: String? = nil

    // Panel show/hide (drives the open/close fade).
    @Published var panelVisible = false {
        didSet { if panelVisible && !oldValue { refreshAwakeCandidates() } }
    }

    /// The internal battery; nil on Macs without one.
    @Published var battery: BatteryMonitor.Reading?

    /// What the menu-bar item shows beside its rings (persisted).
    @Published var menuBarStat: MenuBarStat =
        MenuBarStat(rawValue: UserDefaults.standard.string(forKey: "menuBarStat") ?? "") ?? .none {
        didSet { UserDefaults.standard.set(menuBarStat.rawValue, forKey: "menuBarStat") }
    }

    /// The menu-bar text for `menuBarStat`, or "" for rings only.
    var menuBarText: String {
        switch menuBarStat {
        case .none:    return ""
        case .cpu:     return "\(Int(cpu.rounded()))%"
        case .memory:  return "\(Int(memPct.rounded()))%"
        case .temp:    return cpuTemp > 0 ? "\(Int(cpuTemp.rounded()))°" : "—"
        case .network: return "↓" + compactRate(netDown)
        case .battery: return battery.map { "\($0.percent)%" } ?? ""
        }
    }

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

    private let panelVPadding = panelPadding.top + panelPadding.bottom + panelSectionGap

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

    // MARK: keep awake

    /// How sleep is being prevented; nil = it isn't.
    /// Persisted (except "until a process quits", whose process won't outlive
    /// a relaunch), so a restart or update doesn't quietly let the Mac sleep.
    @Published var awake: AwakeMode? = AwakeMode(stored: UserDefaults.standard.string(forKey: "awakeMode")) {
        didSet { UserDefaults.standard.set(awake?.stored, forKey: "awakeMode"); syncSleep() }
    }
    /// Keep the screen on too, or only the Mac (persisted).
    @Published var keepScreenOn: Bool = UserDefaults.standard.object(forKey: "keepScreenOn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(keepScreenOn, forKey: "keepScreenOn"); syncSleep() }
    }
    /// Busiest processes, offered as "keep awake until this quits".
    @Published var awakeCandidates: [ProcInfo] = []

    var preventSleep: Bool { awake != nil }

    func toggleSleep() { awake = awake == nil ? .indefinitely : nil }

    func keepAwake(minutes: Int) { awake = .until(Date().addingTimeInterval(Double(minutes) * 60)) }

    func keepAwake(whileRunning p: ProcInfo) { awake = .whileRunning(pid: p.id, name: p.name) }

    /// "Until 3:45 PM", "Until python3 quits", "Screen stays on" — under the button.
    var awakeSubtitle: String {
        switch awake {
        case nil:
            return keepScreenOn ? "Mac and screen stay on" : "Mac stays on, screen can sleep"
        case .indefinitely?:
            return "Until you turn it off"
        case .until(let d)?:
            return "Until \(d.formatted(date: .omitted, time: .shortened))"
        case .whileRunning(_, let name)?:
            return "Until \(name) quits"
        }
    }

    private func syncSleep() { sleepManager.set(enabled: awake != nil, display: keepScreenOn) }

    /// End a timed or process-bound keep-awake once its time is up or its
    /// process is gone.
    private func checkAwake() {
        switch awake {
        case .until(let d)? where Date() >= d:
            awake = nil
        case .whileRunning(let pid, _)? where Darwin.kill(pid, 0) != 0 && errno == ESRCH:
            awake = nil
        default:
            break
        }
    }

    private func refreshAwakeCandidates() {
        Task {
            let own = ProcessInfo.processInfo.processIdentifier
            awakeCandidates = await procSampler.top(for: .cpu, limit: 12)
                .filter { $0.id != own && $0.id > 1 && !["kernel_task", "WindowServer", "ps"].contains($0.name) }
                .prefix(8).map { $0 }
        }
    }

    // Toggles
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
    private var firstNet: (down: UInt64, up: UInt64)?
    private var prevNetTime: Date?
    private lazy var cleaner = KeyboardCleaner { [weak self] in
        self?.cleaning = false
    }

    private var timer: Timer?

    init() {
        syncSleep()
        sample()
        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 0.5
        timer = t
    }

    private func tick() {
        sample()
        checkAwake()
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
        let b = BatteryMonitor.read()
        if b != battery { battery = b }

        push(&cpuHistory, cpu)
        push(&memHistory, memUsed)
        push(&diskHistory, diskUsedPct)
        push(&netHistory, netDown + netUp)
        push(&netDownHistory, netDown)
        push(&netUpHistory, netUp)
    }

    /// The SMC read runs on ThermalMonitor's actor (off main — it can sleep a few
    /// ms retrying flaky Apple Silicon sensors); the results land back on main.
    private func sampleThermal() {
        Task {
            let t = await thermal.read()
            cpuTemp = t.cpuTemp; gpuTemp = t.gpuTemp
            fanRPM = t.fanRPM; fanMin = t.fanMin; fanMax = t.fanMax
            fanCount = t.fanCount
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
        if firstNet == nil { firstNet = n }
        if let f = firstNet {
            netSessionDown = n.down >= f.down ? Double(n.down - f.down) : 0
            netSessionUp = n.up >= f.up ? Double(n.up - f.up) : 0
        }
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
            case EPERM: showNote("“\(proc.name)” needs admin to quit")
            case ESRCH: break   // already gone — the refresh will drop it
            default:    showNote("Couldn’t quit “\(proc.name)”")
            }
        }
        // Give the process a beat to exit before re-sampling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refreshProcesses()
        }
    }

    private var noteToken = 0
    private func showNote(_ text: String, for seconds: Double = 3) {
        note = text
        noteToken += 1
        let token = noteToken
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.noteToken == token else { return }
            self.note = nil
        }
    }

    private func refreshProcesses() {
        guard let res = selected else { return }
        Task {
            let rows = await procSampler.top(for: res, limit: 40)
            processCache[res] = rows
        }
    }

    // MARK: derived display helpers
    var memPct: Double { memTotal > 0 ? memUsed / memTotal * 100 : 0 }
    var diskUsedPct: Double { diskTotal > 0 ? (diskTotal - diskFree) / diskTotal * 100 : 0 }

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
        if cleaning { cleaner.stop(); cleaning = false; return }
        do {
            try cleaner.start()
            cleaning = true
        } catch KeyboardCleaner.StartError.notTrusted {
            showNote("Allow MenuLite in Privacy & Security ▸ Accessibility", for: 6)
        } catch {
            // Trusted, yet the tap was refused: macOS applies a new grant only
            // to processes launched after it.
            showNote("Quit and reopen MenuLite to finish enabling Accessibility", for: 6)
        }
    }
}
