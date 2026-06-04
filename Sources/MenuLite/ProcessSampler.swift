import Foundation
import Darwin

/// Produces "what's eating this resource" process lists.
/// CPU/memory come from `ps`; disk I/O comes from libproc `proc_pid_rusage`
/// (sampled twice to get a per-second rate).
final class ProcessSampler {
    private var prevDiskBytes: [Int32: UInt64] = [:]
    private var prevDiskTime: Date?

    func top(for resource: Resource, limit: Int = 6) -> [ProcInfo] {
        switch resource {
        case .cpu:     return topCPU(limit: limit)
        case .memory:  return topMemory(limit: limit)
        case .disk:    return topDiskIO(limit: limit)
        case .network: return []   // per-process network needs elevated privileges
        }
    }

    // MARK: ps-based
    private func topCPU(limit: Int) -> [ProcInfo] {
        let lines = runPS(["-Aceo", "pid=,pcpu=,comm=", "-r"])
        var out: [ProcInfo] = []
        for line in lines {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]) else { continue }
            out.append(ProcInfo(id: pid, name: String(parts[2]),
                                value: cpu, display: String(format: "%.0f%%", cpu)))
            if out.count >= limit { break }
        }
        return out
    }

    private func topMemory(limit: Int) -> [ProcInfo] {
        let lines = runPS(["-Axceo", "pid=,rss=,comm=", "-m"])
        var out: [ProcInfo] = []
        for line in lines {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int32(parts[0]),
                  let rssKB = Double(parts[1]) else { continue }
            let bytes = rssKB * 1024
            out.append(ProcInfo(id: pid, name: String(parts[2]),
                                value: bytes, display: fmtBytes(bytes)))
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: libproc disk I/O
    private func topDiskIO(limit: Int) -> [ProcInfo] {
        let now = Date()
        let dt = prevDiskTime.map { now.timeIntervalSince($0) } ?? 0
        prevDiskTime = now

        var current: [Int32: UInt64] = [:]
        var rates: [(pid: Int32, bps: Double)] = []

        for pid in livePIDs() {
            guard let io = diskBytes(pid: pid) else { continue }
            let total = io.read + io.written
            current[pid] = total
            if dt > 0, let prev = prevDiskBytes[pid], total >= prev {
                let bps = Double(total - prev) / dt
                if bps > 0 { rates.append((pid, bps)) }
            }
        }
        prevDiskBytes = current

        rates.sort { $0.bps > $1.bps }
        return rates.prefix(limit).map { r in
            ProcInfo(id: r.pid, name: procName(r.pid),
                     value: r.bps, display: fmtBytes(r.bps) + "/s")
        }
    }

    private func livePIDs() -> [Int32] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }
        let count = Int(needed) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: count)
        let got = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, needed)
        guard got > 0 else { return [] }
        return pids.filter { $0 > 0 }
    }

    private func diskBytes(pid: Int32) -> (read: UInt64, written: UInt64)? {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) { p -> Int32 in
            p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }
        guard rc == 0 else { return nil }
        return (info.ri_diskio_bytesread, info.ri_diskio_byteswritten)
    }

    private func procName(_ pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        let n = proc_name(pid, &buf, 256)
        return n > 0 ? String(cString: buf) : "pid \(pid)"
    }

    // MARK: helpers
    private func runPS(_ args: [String]) -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let s = String(data: data, encoding: .utf8) else { return [] }
        return s.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }
}

func fmtBytes(_ n: Double) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .memory
    f.allowedUnits = n >= 1_000_000_000 ? [.useGB] : [.useMB, .useKB]
    return f.string(fromByteCount: Int64(n))
}
