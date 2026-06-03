import Foundation
import Darwin

/// Samples CPU, memory and disk using low-level system APIs (no shelling out).
final class StatsMonitor {
    // CPU needs the delta between two samples of cumulative tick counters.
    private var prevTotal: Double = 0
    private var prevBusy: Double = 0

    func cpuUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle

        defer { prevBusy = busy; prevTotal = total }
        let dBusy = busy - prevBusy
        let dTotal = total - prevTotal
        guard dTotal > 0 else { return 0 }
        return max(0, min(100, dBusy / dTotal * 100))
    }

    func memory() -> (used: Double, total: Double) {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, total) }
        let page = Double(vm_kernel_page_size)
        // "App memory" + wired + compressed ≈ what Activity Monitor calls used.
        let used = (Double(stats.active_count)
                    + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * page
        return (used, total)
    }

    func disk() -> (free: Double, total: Double) {
        let url = URL(fileURLWithPath: "/")
        guard let v = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey
        ]) else { return (0, 1) }
        let free = Double(v.volumeAvailableCapacityForImportantUsage ?? 0)
        let total = Double(v.volumeTotalCapacity ?? 1)
        return (free, total)
    }
}
