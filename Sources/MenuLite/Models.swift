import SwiftUI

enum Resource: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "MEM"
    case disk = "DISK"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cpu:    return "cpu"
        case .memory: return "memorychip"
        case .disk:   return "internaldrive"
        }
    }

    /// What the drill-in process list is ranked by.
    var processHeading: String {
        switch self {
        case .cpu:    return "Top processes · CPU"
        case .memory: return "Top processes · memory"
        case .disk:   return "Top processes · disk I/O"
        }
    }
}

/// One row in a drill-in process list.
struct ProcInfo: Identifiable {
    let id: Int32        // pid
    let name: String
    let value: Double    // metric magnitude (for sorting)
    let display: String  // formatted value, e.g. "36%", "1.2 GB", "4.4 MB/s"
}

func loadColor(_ pct: Double) -> Color {
    switch pct {
    case ..<60:  return .green
    case ..<85:  return .orange
    default:     return .red
    }
}
