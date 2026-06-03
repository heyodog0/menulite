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

    // Toggles
    @Published var preventSleep = false {
        didSet { sleepManager.setEnabled(preventSleep) }
    }
    @Published var dimLevel: Double = 0 {    // 0…0.9 overlay alpha for external displays
        didSet { dimmer.setDim(dimLevel) }
    }
    @Published var cleaning = false

    private let sleepManager = SleepManager()
    private let stats = StatsMonitor()
    private let dimmer = DisplayDimmer()
    private lazy var cleaner = KeyboardCleaner { [weak self] in
        // Called when cleaning ends (Done button, or failure).
        self?.cleaning = false
    }

    private var timer: Timer?

    init() {
        sample()
        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        t.tolerance = 0.5
        timer = t
    }

    private func sample() {
        cpu = stats.cpuUsage()
        let m = stats.memory()
        memUsed = m.used; memTotal = m.total
        let d = stats.disk()
        diskFree = d.free; diskTotal = d.total
    }

    // MARK: derived display helpers
    var memPct: Double { memTotal > 0 ? memUsed / memTotal * 100 : 0 }
    var diskUsedPct: Double { diskTotal > 0 ? (diskTotal - diskFree) / diskTotal * 100 : 0 }

    var menuBarLabel: String {
        String(format: "C%.0f M%.0f", cpu, memPct)
    }

    func toggleCleaning() {
        if cleaning {
            cleaner.stop()
            cleaning = false
        } else {
            cleaning = cleaner.start()
        }
    }
}
