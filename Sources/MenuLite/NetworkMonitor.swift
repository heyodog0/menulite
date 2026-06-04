import Foundation
import Darwin

/// Reads cumulative in/out bytes across active non-loopback interfaces.
/// Deltas between samples give throughput.
final class NetworkMonitor {
    func sample() -> (down: UInt64, up: UInt64) {
        var down: UInt64 = 0, up: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ptr) == 0 else { return (0, 0) }
        defer { freeifaddrs(ptr) }

        var cur = ptr
        while let c = cur {
            defer { cur = c.pointee.ifa_next }
            guard let addr = c.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: c.pointee.ifa_name)
            if name.hasPrefix("lo") || name.hasPrefix("utun") || name.hasPrefix("awdl") {
                continue
            }
            if let raw = c.pointee.ifa_data {
                let d = raw.assumingMemoryBound(to: if_data.self).pointee
                down += UInt64(d.ifi_ibytes)
                up += UInt64(d.ifi_obytes)
            }
        }
        return (down, up)
    }
}
