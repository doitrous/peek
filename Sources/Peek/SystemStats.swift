import Foundation
import Darwin
import IOKit.ps

struct SystemSnapshot: Equatable {
    var cpuPercent: Double = 0
    var memUsedGB: Double = 0
    var memTotalGB: Double = 0
    var batteryPercent: Int?          // nil on desktops
    var memPercent: Double { memTotalGB > 0 ? memUsedGB / memTotalGB * 100 : 0 }
}

/// Samples CPU / memory / battery on a cheap 2s timer so the switcher can show
/// them instantly. CPU % is a delta between ticks (needs two samples to warm up).
final class SystemStats {
    private(set) var current = SystemSnapshot()
    var onUpdate: ((SystemSnapshot) -> Void)?

    private var timer: Timer?
    private var lastCPU: (used: Double, total: Double)?
    private let totalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

    func start() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
    }

    private func sample() {
        var snap = SystemSnapshot()
        snap.cpuPercent = cpuPercent()
        let (used, _) = memoryUsage()
        snap.memUsedGB = used
        snap.memTotalGB = totalGB
        snap.batteryPercent = batteryPercent()
        current = snap
        onUpdate?(snap)
    }

    private func cpuPercent() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return current.cpuPercent }
        let user = Double(info.cpu_ticks.0), sys = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2), nice = Double(info.cpu_ticks.3)
        let used = user + sys + nice
        let total = used + idle
        defer { lastCPU = (used, total) }
        guard let last = lastCPU else { return 0 }
        let dTotal = total - last.total, dUsed = used - last.used
        guard dTotal > 0 else { return current.cpuPercent }
        return min(100, max(0, dUsed / dTotal * 100))
    }

    private func memoryUsage() -> (usedGB: Double, totalGB: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (current.memUsedGB, totalGB) }
        let page = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * page
        return (used / 1_073_741_824, totalGB)
    }

    private func batteryPercent() -> Int? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let cur = desc[kIOPSCurrentCapacityKey as String] as? Int,
                  let max = desc[kIOPSMaxCapacityKey as String] as? Int, max > 0 else { continue }
            return Int((Double(cur) / Double(max) * 100).rounded())
        }
        return nil
    }
}
