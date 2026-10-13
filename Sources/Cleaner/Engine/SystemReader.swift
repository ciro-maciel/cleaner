import Foundation
import Darwin
import IOKit
import IOKit.ps
import AppKit

/// One reading of the whole machine. Rates (CPU %, bytes per second) come from the difference
/// against the previous reading, so the first one after start has them at zero.
struct SystemSample {
    struct CPU {
        var user: Double = 0        // 0...1 of all cores
        var system: Double = 0
        var cores: [Double] = []    // 0...1 per logical core
        var load: (Double, Double, Double) = (0, 0, 0)
        var total: Double { user + system }
    }
    struct Memory {
        var total: Int64 = 0
        var app: Int64 = 0
        var wired: Int64 = 0
        var compressed: Int64 = 0
        var cached: Int64 = 0
        var free: Int64 = 0          // pages nobody holds right now
        var swapUsed: Int64 = 0
        var swapTotal: Int64 = 0
        var pressure: Int = 1       // 1 normal, 2 warning, 4 critical (kern.memorystatus_vm_pressure_level)
        var available: Double = 1   // 0...1, kern.memorystatus_level
        var used: Int64 { app + wired + compressed }
    }
    struct Disk {
        var total: Int64 = 0
        var free: Int64 = 0
        var readPerSec: Int64 = 0
        var writePerSec: Int64 = 0
    }
    struct Network {
        var inPerSec: Int64 = 0
        var outPerSec: Int64 = 0
        var totalIn: Int64 = 0       // since boot, on the counted interfaces
        var totalOut: Int64 = 0
        var interface: String = ""
        var address: String = ""
    }
    struct Battery {
        var percent: Int = 0
        var charging = false
        var onAC = false
        var minutesLeft: Int?        // to empty, or to full while charging
        var cycles: Int?
        var health: Double?          // max capacity / design capacity
        var temperature: Double?     // °C, from the battery's own sensor
        var watts: Double?           // + charging, − discharging
        var adapterWatts: Int?
    }

    var date = Date()
    var cpu = CPU()
    var gpu: Double?                 // 0...1, nil when the GPU does not report it
    var memory = Memory()
    var disk = Disk()
    var network = Network()
    var battery: Battery?
    var thermal: ProcessInfo.ThermalState = .nominal
    var uptime: TimeInterval = 0
}

struct ProcessRow: Identifiable, Hashable {
    var id: Int32 { pid }
    let pid: Int32
    let name: String
    let cpu: Double        // % of one core, as Activity Monitor and ps show it
    let memory: Int64      // resident bytes
}

/// Reads counters from the kernel and IOKit. Not thread safe: one sampler drives it.
final class SystemReader: @unchecked Sendable {
    private var lastTicks: [[UInt32]] = []
    private var lastDisk: (read: UInt64, write: UInt64, at: Date)?
    private var lastNet: (inBytes: UInt64, outBytes: UInt64, at: Date)?

    let coreLayout: (performance: Int, efficiency: Int) = {
        (SystemReader.sysctlInt("hw.perflevel0.logicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount,
         SystemReader.sysctlInt("hw.perflevel1.logicalcpu") ?? 0)
    }()

    let model: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }()

    func sample() -> SystemSample {
        var s = SystemSample()
        s.cpu = readCPU()
        s.gpu = readGPU()
        s.memory = readMemory()
        s.disk = readDisk()
        s.network = readNetwork()
        s.battery = readBattery()
        s.thermal = ProcessInfo.processInfo.thermalState
        s.uptime = ProcessInfo.processInfo.systemUptime
        return s
    }

    // MARK: CPU — host_processor_info ticks per core

    private func readCPU() -> SystemSample.CPU {
        var cpu = SystemSample.CPU()
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return cpu }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var ticks: [[UInt32]] = []
        for i in 0..<Int(count) {
            let base = i * Int(CPU_STATE_MAX)
            ticks.append([UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                          UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                          UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                          UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])])
        }
        if lastTicks.count == ticks.count {
            var user = 0.0, system = 0.0, all = 0.0
            for (now, before) in zip(ticks, lastTicks) {
                let d = zip(now, before).map { Double($0 &- $1) }
                let total = d.reduce(0, +)
                user += d[0] + d[3]; system += d[1]; all += total
                cpu.cores.append(total > 0 ? (d[0] + d[1] + d[3]) / total : 0)
            }
            if all > 0 { cpu.user = user / all; cpu.system = system / all }
        } else {
            cpu.cores = Array(repeating: 0, count: ticks.count)
        }
        lastTicks = ticks
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        cpu.load = (loads[0], loads[1], loads[2])
        return cpu
    }

    // MARK: GPU — IOAccelerator performance statistics

    private func readGPU() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                  let value = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber else { continue }
            best = max(best ?? 0, value.doubleValue / 100)
        }
        return best
    }

    // MARK: Memory — host_statistics64, the same split as Activity Monitor

    private func readMemory() -> SystemSample.Memory {
        var m = SystemSample.Memory()
        m.total = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        if result == KERN_SUCCESS {
            let page = Int64(vm_kernel_page_size)
            m.app = (Int64(stats.internal_page_count) - Int64(stats.purgeable_count)) * page
            m.wired = Int64(stats.wire_count) * page
            m.compressed = Int64(stats.compressor_page_count) * page
            m.cached = (Int64(stats.purgeable_count) + Int64(stats.external_page_count)) * page
            m.free = (Int64(stats.free_count) + Int64(stats.speculative_count)) * page
        }
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            m.swapUsed = Int64(swap.xsu_used)
            m.swapTotal = Int64(swap.xsu_total)
        }
        m.pressure = SystemReader.sysctlInt("kern.memorystatus_vm_pressure_level") ?? 1
        if let level = SystemReader.sysctlInt("kern.memorystatus_level") { m.available = Double(level) / 100 }
        return m
    }

    // MARK: Disk — volume capacity + IOBlockStorageDriver byte counters

    private func readDisk() -> SystemSample.Disk {
        var d = SystemSample.Disk()
        if let v = DiskUsage.volume() { d.total = v.total; d.free = v.available }
        var read: UInt64 = 0, write: UInt64 = 0
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS {
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                if let stats = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any] {
                    read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                    write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
                }
                IOObjectRelease(entry)
            }
            IOObjectRelease(iterator)
        }
        let now = Date()
        if let last = lastDisk, read >= last.read, write >= last.write {
            let dt = max(now.timeIntervalSince(last.at), 0.001)
            d.readPerSec = Int64(Double(read - last.read) / dt)
            d.writePerSec = Int64(Double(write - last.write) / dt)
        }
        lastDisk = (read, write, now)
        return d
    }

    // MARK: Network — 64-bit counters from NET_RT_IFLIST2, Wi-Fi and Ethernet (en*) only

    private func readNetwork() -> SystemSample.Network {
        var n = SystemSample.Network()
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        var inBytes: UInt64 = 0, outBytes: UInt64 = 0
        var busiest: (name: String, bytes: UInt64) = ("", 0)
        if sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 {
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: len, alignment: 8)
            defer { buffer.deallocate() }
            if sysctl(&mib, 6, buffer, &len, nil, 0) == 0 {
                var offset = 0
                while offset + MemoryLayout<if_msghdr>.size <= len {
                    let header = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                    if Int32(header.ifm_type) == RTM_IFINFO2 {
                        let msg = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                        var nameBuf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                        let name = if_indextoname(UInt32(msg.ifm_index), &nameBuf).map { String(cString: $0) } ?? ""
                        let up = (msg.ifm_flags & IFF_UP) != 0 && (msg.ifm_flags & IFF_RUNNING) != 0
                        if up && name.hasPrefix("en") {
                            inBytes += msg.ifm_data.ifi_ibytes
                            outBytes += msg.ifm_data.ifi_obytes
                            let both = msg.ifm_data.ifi_ibytes + msg.ifm_data.ifi_obytes
                            if both > busiest.bytes { busiest = (name, both) }
                        }
                    }
                    guard header.ifm_msglen > 0 else { break }
                    offset += Int(header.ifm_msglen)
                }
            }
        }
        n.totalIn = Int64(inBytes)
        n.totalOut = Int64(outBytes)
        n.interface = busiest.name
        n.address = SystemReader.ipv4(of: busiest.name) ?? ""
        let now = Date()
        if let last = lastNet, inBytes >= last.inBytes, outBytes >= last.outBytes {
            let dt = max(now.timeIntervalSince(last.at), 0.001)
            n.inPerSec = Int64(Double(inBytes - last.inBytes) / dt)
            n.outPerSec = Int64(Double(outBytes - last.outBytes) / dt)
        }
        lastNet = (inBytes, outBytes, now)
        return n
    }

    private static func ipv4(of interface: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard !interface.isEmpty, getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            guard String(cString: ifa.pointee.ifa_name) == interface, let addr = ifa.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }

    // MARK: Battery — IOPowerSources + the AppleSmartBattery registry entry

    private func readBattery() -> SystemSample.Battery? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        var battery: SystemSample.Battery?
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            var b = SystemSample.Battery()
            let current = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            b.percent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0
            b.charging = d[kIOPSIsChargingKey] as? Bool ?? false
            b.onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let minutes = (b.charging ? d[kIOPSTimeToFullChargeKey] : d[kIOPSTimeToEmptyKey]) as? Int ?? -1
            b.minutesLeft = minutes > 0 ? minutes : nil
            battery = b
        }
        guard var b = battery else { return nil }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                b.cycles = dict["CycleCount"] as? Int
                let maxCap = (dict["AppleRawMaxCapacity"] as? Int) ?? (dict["MaxCapacity"] as? Int)
                if let maxCap, let design = dict["DesignCapacity"] as? Int, design > 0, maxCap > 100 {
                    b.health = Double(maxCap) / Double(design)
                }
                if let t = dict["Temperature"] as? Int { b.temperature = Double(t) / 100 }
                if let mv = (dict["Voltage"] as? NSNumber)?.doubleValue,
                   let raw = (dict["InstantAmperage"] ?? dict["Amperage"]) as? NSNumber {
                    // A signed value that some models report as unsigned 64 or 16 bit.
                    var ma = Int64(truncatingIfNeeded: raw.uint64Value)
                    if ma > 32_767 && ma < 65_536 { ma = Int64(Int16(truncatingIfNeeded: ma)) }
                    b.watts = mv / 1000 * Double(ma) / 1000
                }
                if let adapter = dict["AdapterDetails"] as? [String: Any] { b.adapterWatts = adapter["Watts"] as? Int }
            }
        }
        return b
    }

    // MARK: Processes — ps sees every process without root; its %CPU is a recent average

    static func topProcesses() -> [ProcessRow] {
        let out = Privileged.run("/bin/ps", ["-Aceo", "pid=,pcpu=,rss=,comm="]).output
        var rows: [ProcessRow] = []
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let cpu = Double(parts[1].replacingOccurrences(of: ",", with: ".")),
                  let rss = Int64(parts[2]) else { continue }
            rows.append(ProcessRow(pid: pid, name: String(parts[3]), cpu: cpu, memory: rss * 1024))
        }
        return rows
    }

    // MARK: Free memory — /usr/sbin/purge through the privileged helper (no password)

    func freeBytes() -> Int64 { readMemory().free }

    // MARK: helpers

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        // Some entries are 32-bit.
        return size == MemoryLayout<Int32>.size ? Int(Int32(truncatingIfNeeded: value)) : Int(value)
    }
}
