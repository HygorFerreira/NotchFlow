import Foundation
import Darwin

/// System-wide counters. CPU usage is measured between samples, across all cores.
struct MachineUsage {
    struct CPUTicks {
        let user: UInt32
        let system: UInt32
        let idle: UInt32
        let nice: UInt32

        func usage(since previous: CPUTicks) -> Double? {
            // Kernel counters can wrap; subtract before widening to UInt64.
            let busy = UInt64(user &- previous.user) + UInt64(system &- previous.system)
                + UInt64(nice &- previous.nice)
            let total = busy + UInt64(idle &- previous.idle)
            return total > 0 ? Double(busy) / Double(total) : nil
        }
    }

    static func cpuTicks() -> CPUTicks? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1,
                        idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    /// Active, wired and compressed physical memory; excludes reclaimable inactive pages.
    static func usedMemory() -> UInt64? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        return (UInt64(info.active_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)) * UInt64(pageSize)
    }
}
