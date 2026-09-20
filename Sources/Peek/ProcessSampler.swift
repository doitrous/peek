import Foundation
import Darwin

struct AppUsage: Equatable {
    var cpuPercent: Double
    var memMB: Double
}

/// Per-process CPU% and memory for a small set of pids.
///
/// Optimized on purpose: it samples ONLY the pids currently on screen, ONLY
/// while the switcher is visible, and CPU% is a delta against a tiny cached
/// prior sample. No global process scan, no continuous background polling — so
/// it adds negligible CPU/RAM to Peek itself. `proc_pid_rusage` is a cheap
/// per-pid syscall; same-user apps only (system procs return an error → skipped).
final class ProcessSampler {
    private var last: [pid_t: (cpuSecs: Double, at: CFAbsoluteTime)] = [:]
    private let cores = Double(ProcessInfo.processInfo.activeProcessorCount)

    func sample(pids: Set<pid_t>) -> [pid_t: AppUsage] {
        let now = CFAbsoluteTimeGetCurrent()
        var out: [pid_t: AppUsage] = [:]
        for pid in pids {
            guard let ri = Self.rusage(pid) else { continue }
            let cpuSecs = Double(ri.ri_user_time &+ ri.ri_system_time) / 1_000_000_000
            let memMB = Double(ri.ri_phys_footprint) / (1024 * 1024)
            var cpu = 0.0
            if let prev = last[pid], now > prev.at {
                cpu = max(0, (cpuSecs - prev.cpuSecs) / (now - prev.at) * 100)
            }
            last[pid] = (cpuSecs, now)
            out[pid] = AppUsage(cpuPercent: min(cpu, cores * 100), memMB: memMB)
        }
        last = last.filter { pids.contains($0.key) }   // keep the cache tiny
        return out
    }

    private static func rusage(_ pid: pid_t) -> rusage_info_v2? {
        var info = rusage_info_v2()
        let ok = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        return ok == 0 ? info : nil
    }
}
