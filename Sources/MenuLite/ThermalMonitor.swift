import Foundation
import IOKit

/// Reads CPU/GPU die temperature and fan speed straight from the Apple SMC via
/// IOKit — no shelling out, matching StatsMonitor's low-level approach.
///
/// Apple exposes no public thermal API, so we talk to the "AppleSMC" user client
/// directly: ask for a key's info (size + type), then read its bytes. On Apple
/// Silicon the per-core temp sensors are `flt` (little-endian Float32). The
/// correct die-sensor key set differs per chip; the sets below mirror smctemp /
/// exelban's Stats, which is the same data the user already sanity-checked.
final class ThermalMonitor {

    // MARK: C ABI structs (must match AppleSMC's 80-byte key-data struct exactly)

    private struct KeyDataVers { var major: UInt8 = 0; var minor: UInt8 = 0
        var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
    private struct KeyDataPLimit { var version: UInt16 = 0; var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
    // The trailing pad bytes are load-bearing: C pads this struct to 12 bytes, so
    // without them the enclosing KeyData is 76 bytes and the kernel rejects the
    // call (it expects 80). They force `bytes` to land at offset 48, matching C.
    private struct KeyDataKeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0; var pad0: UInt8 = 0; var pad1: UInt8 = 0; var pad2: UInt8 = 0 }
    private typealias Bytes32 = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    private struct KeyData {
        var key: UInt32 = 0
        var vers = KeyDataVers()
        var pLimit = KeyDataPLimit()
        var keyInfo = KeyDataKeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes32 = (0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
                              0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0)
    }

    private let kKernelIndexSMC: UInt32 = 2
    private let kSMCReadBytes: UInt8 = 5
    private let kSMCGetKeyInfo: UInt8 = 9
    private let kTypeFlt: UInt32 = ThermalMonitor.fcc("flt ")
    private let kTypeUi8: UInt32 = ThermalMonitor.fcc("ui8 ")
    private let kTypeUi16: UInt32 = ThermalMonitor.fcc("ui16")
    private let kTypeUi32: UInt32 = ThermalMonitor.fcc("ui32")

    // Apple Silicon CPU/GPU sensors go "not ready" in bursts and return 0; hold
    // the last good reading so the UI never blanks mid-stream (like smctemp -n).
    private var lastCPU = 0.0
    private var lastGPU = 0.0

    private var conn: io_connect_t = 0
    private var opened = false
    // Key info (size/type) never changes for a key — cache it to avoid a syscall.
    private var infoCache: [UInt32: KeyDataKeyInfo] = [:]

    // Sensor key sets per chip (CPU performance/efficiency die sensors, GPU clusters).
    private let cpuKeys: [String]
    private let gpuKeys: [String]

    init() {
        let model = ThermalMonitor.cpuModel()
        (cpuKeys, gpuKeys) = ThermalMonitor.keySets(for: model)
        open()
    }

    deinit { if opened { IOServiceClose(conn) } }

    // MARK: public reads

    struct Reading {
        var cpuTemp: Double = 0   // °C, 0 if unavailable
        var gpuTemp: Double = 0
        var fanRPM: Double = 0
        var fanMin: Double = 0
        var fanMax: Double = 0
        var fanCount: Int = 0
    }

    /// NOT main-thread safe and may sleep up to a few ms retrying — call off the
    /// main thread (AppState does, from a detached task).
    func read() -> Reading {
        guard opened else { return Reading() }
        var r = Reading()

        // Retry a short burst; if every sensor is "not ready", fall back to last good.
        let cpu = stableAverage(cpuKeys)
        if cpu > 0 { lastCPU = cpu }
        r.cpuTemp = cpu > 0 ? cpu : lastCPU

        let gpu = stableAverage(gpuKeys)
        if gpu > 0 { lastGPU = gpu }
        r.gpuTemp = gpu > 0 ? gpu : lastGPU

        r.fanCount = Int(value(forKey: "FNum").rounded())
        if r.fanCount > 0 {
            // Read fan 0 (laptops report all fans in lockstep; fan 0 is representative).
            r.fanRPM = value(forKey: "F0Ac")
            r.fanMin = value(forKey: "F0Mn")
            r.fanMax = value(forKey: "F0Mx")
        }
        return r
    }

    // MARK: averaging (skip sensors outside a sane range, like smctemp)

    /// Average the valid sensors, retrying a few times if the whole set reads 0.
    private func stableAverage(_ keys: [String]) -> Double {
        for attempt in 0..<8 {
            let v = average(keys, low: 10, high: 120)
            if v > 0 { return v }
            if attempt < 7 { usleep(4000) }   // ~4ms between bursts, ≤28ms total
        }
        return 0
    }

    private func average(_ keys: [String], low: Double, high: Double) -> Double {
        var sum = 0.0, n = 0
        for k in keys {
            let v = value(forKey: k)
            if v > low && v < high { sum += v; n += 1 }
        }
        return n > 0 ? sum / Double(n) : 0
    }

    // MARK: SMC plumbing

    private func open() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        opened = (kr == kIOReturnSuccess)
    }

    private func call(_ input: inout KeyData, _ output: inout KeyData) -> kern_return_t {
        let size = MemoryLayout<KeyData>.stride
        var outSize = size
        return IOConnectCallStructMethod(
            conn, kKernelIndexSMC, &input, size, &output, &outSize)
    }

    private func keyInfo(_ key: UInt32) -> KeyDataKeyInfo? {
        if let cached = infoCache[key] { return cached }
        var input = KeyData(); input.key = key; input.data8 = kSMCGetKeyInfo
        var output = KeyData()
        guard call(&input, &output) == kIOReturnSuccess else { return nil }
        infoCache[key] = output.keyInfo
        return output.keyInfo
    }

    /// Returns the decoded value for `key`, or 0 if it can't be read.
    private func value(forKey keyStr: String) -> Double {
        let key = ThermalMonitor.fcc(keyStr)
        guard let info = keyInfo(key), info.dataSize > 0 else { return 0 }

        var input = KeyData()
        input.key = key
        input.keyInfo.dataSize = info.dataSize
        input.data8 = kSMCReadBytes
        var output = KeyData()
        guard call(&input, &output) == kIOReturnSuccess else { return 0 }

        // Copy the fixed-size byte tuple into an array we can index.
        var buf = [UInt8](repeating: 0, count: 32)
        withUnsafeBytes(of: output.bytes) { raw in
            for i in 0..<32 { buf[i] = raw[i] }
        }

        // Apple Silicon temps + fans are `flt` (little-endian Float32).
        if info.dataType == kTypeFlt, info.dataSize >= 4 {
            var f: Float32 = 0
            memcpy(&f, buf, 4)
            return Double(f)
        }
        // Unsigned integers (e.g. FNum is ui8) — big-endian.
        if info.dataType == kTypeUi8 || info.dataType == kTypeUi16
            || info.dataType == kTypeUi32 {
            var u = 0
            for i in 0..<Int(info.dataSize) { u = u * 256 + Int(buf[i]) }
            return Double(u)
        }
        if info.dataSize == 2 {   // sp78: signed 8.8 fixed point, big-endian
            let raw = (Int(buf[0]) << 8) | Int(buf[1])
            return Double(raw) / 256.0
        }
        return 0
    }

    // MARK: helpers

    /// Pack a (≤4 char) key string into the big-endian FourCharCode the SMC wants.
    private static func fcc(_ s: String) -> UInt32 {
        var r: UInt32 = 0
        for b in s.utf8.prefix(4) { r = (r << 8) | UInt32(b) }
        return r
    }

    private static func cpuModel() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        return String(cString: buf).lowercased()
    }

    /// CPU + GPU die-sensor keys per Apple Silicon generation (mirrors smctemp).
    private static func keySets(for model: String) -> (cpu: [String], gpu: [String]) {
        if model.contains("m5") {
            return (["Tp00","Tp04","Tp08","Tp0C","Tp0G","Tp0K","Tp0O","Tp0R",
                     "Tp0U","Tp0X","Tp0a","Tp0d","Tp0g","Tp0j","Tp0m","Tp0p",
                     "Tp0u","Tp0y"],
                    ["Tg0U","Tg0X","Tg0d","Tg0g","Tg0j","Tg1Y","Tg1c","Tg1g"])
        }
        if model.contains("m4") {
            return (["Tp01","Tp09","Tp0f","Tp05","Tp0D"],
                    ["Tg0D","Tg0P","Tg0X","Tg0j"])
        }
        if model.contains("m3") {
            return (["Tp01","Tp09","Tp0f","Tp0n","Tp05","Tp0D","Tp0j","Tp0r"],
                    ["Tg0D","Tg0P","Tg0X","Tg0b","Tg0j","Tg0v"])
        }
        if model.contains("m2") {
            return (["Tp1h","Tp1t","Tp1p","Tp1l","Tp01","Tp05","Tp09","Tp0D",
                     "Tp0X","Tp0b","Tp0f","Tp0j"],
                    ["Tg0f","Tg0j"])
        }
        // M1 and unknown Apple Silicon
        return (["Tp01","Tp05","Tp0D","Tp0H","Tp0L","Tp0P","Tp0X","Tp0b",
                 "Tp0f","Tp0j"],
                ["Tg05","Tg0D","Tg0L","Tg0T","Tg1b","Tg4b"])
    }
}
