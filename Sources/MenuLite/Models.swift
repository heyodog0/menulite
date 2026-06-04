import SwiftUI

enum Resource: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "MEM"
    case network = "NET"
    case disk = "DISK"

    var id: String { rawValue }

    /// The dials shown on the home screen (network has no %, so no ring).
    static let ringCases: [Resource] = [.cpu, .memory, .disk]

    var icon: String {
        switch self {
        case .cpu:     return "cpu.fill"
        case .memory:  return "memorychip.fill"
        case .network: return "dot.radiowaves.up.forward"
        case .disk:    return "internaldrive.fill"
        }
    }

    var tabTitle: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .network: return "Network"
        case .disk: return "Disk"
        }
    }

    var processHeading: String {
        switch self {
        case .cpu:     return "Top processes · CPU"
        case .memory:  return "Top processes · memory"
        case .network: return "Throughput"
        case .disk:    return "Top processes · disk I/O"
        }
    }
}

/// One row in a drill-in process list.
struct ProcInfo: Identifiable {
    let id: Int32
    let name: String
    let value: Double
    let display: String
}

func loadColor(_ pct: Double) -> Color {
    switch pct {
    case ..<60:  return .green
    case ..<85:  return .orange
    default:     return .red
    }
}

/// Memory is colored by actual memory PRESSURE, not used % (which runs high
/// normally on macOS). 1 = normal → blue, 2 = warning → orange, 4 = critical → red.
func pressureColor(_ level: Int) -> Color {
    switch level {
    case 4:  return .red
    case 2:  return .orange
    default: return .blue
    }
}

/// Format a byte/second rate compactly (1000-based, networking convention).
func fmtRate(_ bps: Double) -> String {
    if bps >= 1_000_000 { return String(format: "%.1f MB/s", bps / 1_000_000) }
    if bps >= 1_000     { return String(format: "%.0f KB/s", bps / 1_000) }
    return String(format: "%.0f B/s", bps)
}
