import Foundation
import IOKit
import IOKit.ps
import SwiftUI

struct BatteryInfo: Equatable {
    var present = false
    var level = 100
    var charging = false
    var onAC = true
    var timeToEmpty: Int?
    var timeToFull: Int?
    var cycles: Int?
    var health: Int?
    var adapterWatts: Int?
}

/// Batterie, CPU, mémoire, disque.
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published var battery = BatteryInfo()
    @Published var cpu: Double = 0
    @Published var memUsed: Double = 0
    let memTotal = Double(ProcessInfo.processInfo.physicalMemory)
    @Published var diskFree: Double = 0
    @Published var diskTotal: Double = 1

    private var timer: Timer?
    private var prevTicks: [UInt32]?
    private var registry: (cycles: Int?, health: Int?) = (nil, nil)
    private var ticks = 0
    private var firstRead = true
    private var lowWarned = false
    private let host = mach_host_self()

    func start() {
        update()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func update() {
        if ticks % 30 == 0 {
            registry = Self.readRegistry()
            readDisk()
        }
        ticks += 1

        var b = Self.readPowerSource()
        b.cycles = registry.cycles
        b.health = registry.health
        handleBatteryEvents(b)
        if b != battery { battery = b }

        cpu = readCPU()
        readMemory()
    }

    private func handleBatteryEvents(_ b: BatteryInfo) {
        defer { firstRead = false }
        guard !firstRead, b.present else { return }
        if b.onAC != battery.onAC, UserDefaults.standard.bool(forKey: "showBatterySneak") {
            NotchState.shared.showSneak(symbol: b.onAC ? "bolt.fill" : Self.symbol(for: b),
                                        text: b.onAC ? "En charge — \(b.level) %" : "Sur batterie — \(b.level) %",
                                        tint: b.onAC ? .green : .white)
        }
        if !b.onAC && b.level <= 20 && !lowWarned {
            lowWarned = true
            NotchState.shared.showSneak(symbol: "battery.25percent", text: "Batterie faible — \(b.level) %",
                                        tint: .red, duration: 5)
        }
        if b.onAC || b.level > 25 { lowWarned = false }
    }

    static func symbol(for b: BatteryInfo) -> String {
        if b.charging || (b.onAC && b.level >= 99) { return "battery.100percent.bolt" }
        switch b.level {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    static func color(for b: BatteryInfo) -> Color {
        if b.charging || b.onAC { return .green }
        if b.level <= 20 { return .red }
        return .white
    }

    static func readPowerSource() -> BatteryInfo {
        var info = BatteryInfo()
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let listRef = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() else { return info }
        let list = listRef as NSArray
        for ps in list {
            guard let descRef = IOPSGetPowerSourceDescription(blob, ps as AnyObject)?.takeUnretainedValue(),
                  let d = descRef as NSDictionary as? [String: Any] else { continue }
            guard (d["Type"] as? String) == "InternalBattery" else { continue }
            info.present = true
            let current = d["Current Capacity"] as? Int ?? 0
            let maxCap = d["Max Capacity"] as? Int ?? 100
            info.level = maxCap > 0 ? Int((Double(current) / Double(maxCap) * 100).rounded()) : current
            info.charging = d["Is Charging"] as? Bool ?? false
            info.onAC = (d["Power Source State"] as? String) == "AC Power"
            if let t = d["Time to Empty"] as? Int, t > 0 { info.timeToEmpty = t }
            if let t = d["Time to Full Charge"] as? Int, t > 0 { info.timeToFull = t }
        }
        if info.onAC,
           let adRef = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue(),
           let ad = adRef as NSDictionary as? [String: Any] {
            info.adapterWatts = ad["Watts"] as? Int
        }
        return info
    }

    static func readRegistry() -> (cycles: Int?, health: Int?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let cf = props?.takeRetainedValue(),
              let dict = cf as NSDictionary as? [String: Any] else { return (nil, nil) }
        let cycles = dict["CycleCount"] as? Int
        var health: Int?
        let maxCap = (dict["AppleRawMaxCapacity"] as? Int) ?? (dict["NominalChargeCapacity"] as? Int)
        if let m = maxCap, let design = dict["DesignCapacity"] as? Int, design > 0 {
            health = min(100, Int((Double(m) / Double(design) * 100).rounded()))
        }
        return (cycles, health)
    }

    private func readCPU() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return cpu }
        let t: [UInt32] = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        defer { prevTicks = t }
        guard let p = prevTicks else { return 0 }
        let user = Double(t[0] &- p[0]), sys = Double(t[1] &- p[1])
        let idle = Double(t[2] &- p[2]), nice = Double(t[3] &- p[3])
        let total = user + sys + idle + nice
        return total > 0 ? (user + sys + nice) / total : 0
    }

    private func readMemory() {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        let page = Double(getpagesize())
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        memUsed = max(0, (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page)
    }

    private func readDisk() {
        let url = URL(fileURLWithPath: "/")
        if let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            diskFree = Double(v.volumeAvailableCapacityForImportantUsage ?? 0)
            diskTotal = Double(max(1, v.volumeTotalCapacity ?? 1))
        }
    }
}
