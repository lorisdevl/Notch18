import Foundation
import CoreWLAN
import CoreLocation
import SwiftUI

struct IfaceAddr: Identifiable, Equatable {
    var id: String { name + ip }
    let name: String
    let ip: String
    let prefix: Int
}

/// Infos réseau (pratique en TP de R&T) : IP, masque, passerelle, DNS, Wi-Fi, débit, ping.
final class NetworkMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = NetworkMonitor()

    @Published var addresses: [IfaceAddr] = []
    @Published var gateway: String?
    @Published var gatewayIface: String?
    @Published var dns: [String] = []
    @Published var publicIP: String?
    @Published var ssid: String?
    @Published var rssi: Int?
    @Published var txRate: Double?
    @Published var channel: Int?
    @Published var down: Double = 0
    @Published var up: Double = 0
    @Published var pingHistory: [Double?] = []
    @Published var lastPing: Double?

    private var timer: Timer?
    private var tickCount = 0
    private var prevCounters: [String: (UInt32, UInt32)] = [:]
    private var prevDate = Date()
    private var pingInFlight = false
    private let location = CLLocationManager()
    private var active = false

    var pingHost: String {
        let h = (UserDefaults.standard.string(forKey: "pingHost") ?? "1.1.1.1").trimmingCharacters(in: .whitespaces)
        return h.isEmpty ? "1.1.1.1" : h
    }

    var lossPercent: Int {
        guard !pingHistory.isEmpty else { return 0 }
        let lost = pingHistory.filter { $0 == nil }.count
        return Int((Double(lost) / Double(pingHistory.count) * 100).rounded())
    }

    var averagePing: Double? {
        let ok = pingHistory.compactMap { $0 }
        return ok.isEmpty ? nil : ok.reduce(0, +) / Double(ok.count)
    }

    func activate() {
        guard !active else { return }
        active = true
        location.delegate = self
        if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
        refreshSlow()
        if publicIP == nil { fetchPublicIP() }
        prevCounters = readCounters()
        prevDate = Date()
        ping()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func deactivate() {
        active = false
        timer?.invalidate()
        timer = nil
    }

    func resetPing() {
        pingHistory = []
        lastPing = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        readWiFi()
    }

    private func tick() {
        tickCount += 1
        // Débit
        let counters = readCounters()
        let now = Date()
        let dt = now.timeIntervalSince(prevDate)
        if dt > 0 {
            var din: UInt64 = 0, dout: UInt64 = 0
            for (name, value) in counters {
                if let p = prevCounters[name] {
                    din += UInt64(value.0 &- p.0)
                    dout += UInt64(value.1 &- p.1)
                }
            }
            down = Double(din) / dt
            up = Double(dout) / dt
        }
        prevCounters = counters
        prevDate = now

        if tickCount % 2 == 0 { ping() }
        if tickCount % 5 == 0 { refreshSlow() }
    }

    private func readCounters() -> [String: (UInt32, UInt32)] {
        var result: [String: (UInt32, UInt32)] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return result }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            guard let sa = p.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK),
                  let data = p.pointee.ifa_data else { continue }
            let name = String(cString: p.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            result[name] = (d.ifi_ibytes, d.ifi_obytes)
        }
        return result
    }

    static func readAddresses() -> [IfaceAddr] {
        var result: [IfaceAddr] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return result }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let flags = Int32(p.pointee.ifa_flags)
            guard let sa = p.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            var prefix = 0
            if let mask = p.pointee.ifa_netmask {
                prefix = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    $0.pointee.sin_addr.s_addr.nonzeroBitCount
                }
            }
            let ip = host.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            result.append(IfaceAddr(name: String(cString: p.pointee.ifa_name), ip: ip, prefix: prefix))
        }
        return result.sorted { $0.name < $1.name }
    }

    private func readWiFi() {
        guard let iface = CWWiFiClient.shared().interface() else {
            ssid = nil; rssi = nil; txRate = nil; channel = nil
            return
        }
        ssid = iface.ssid()
        let r = iface.rssiValue()
        rssi = r == 0 ? nil : r
        let tx = iface.transmitRate()
        txRate = tx > 0 ? tx : nil
        channel = iface.wlanChannel()?.channelNumber
    }

    private func refreshSlow() {
        addresses = Self.readAddresses()
        readWiFi()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let route = Shell.run("/sbin/route", ["-n", "get", "default"]) ?? ""
            var gw: String?
            var iface: String?
            for line in route.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("gateway:") { gw = t.dropFirst(8).trimmingCharacters(in: .whitespaces) }
                if t.hasPrefix("interface:") { iface = t.dropFirst(10).trimmingCharacters(in: .whitespaces) }
            }
            let resolv = (try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8)) ?? ""
            let servers: [String] = resolv.split(separator: "\n").compactMap { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("nameserver") else { return nil }
                return t.dropFirst("nameserver".count).trimmingCharacters(in: .whitespaces)
            }
            DispatchQueue.main.async {
                self?.gateway = gw
                self?.gatewayIface = iface
                self?.dns = Array(servers.prefix(3))
            }
        }
    }

    func fetchPublicIP() {
        publicIP = nil
        guard let url = URL(string: "https://api.ipify.org") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let ip = data.flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { self?.publicIP = (ip?.isEmpty == false) ? ip : "—" }
        }.resume()
    }

    private func ping() {
        guard !pingInFlight else { return }
        let host = pingHost
        guard !host.hasPrefix("-") else { return }
        pingInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let ms = NetworkMonitor.runPing(host)
            DispatchQueue.main.async {
                guard let self else { return }
                self.pingInFlight = false
                self.lastPing = ms
                self.pingHistory.append(ms)
                if self.pingHistory.count > 40 { self.pingHistory.removeFirst(self.pingHistory.count - 40) }
            }
        }
    }

    static func runPing(_ host: String) -> Double? {
        guard let out = Shell.run("/sbin/ping", ["-c", "1", "-t", "2", host]),
              let range = out.range(of: "time=") else { return nil }
        let rest = out[range.upperBound...]
        let number = rest.prefix { $0.isNumber || $0 == "." }
        return Double(number)
    }
}

// MARK: - Vue Réseau & système

struct NetworkView: View {
    @ObservedObject var net = NetworkMonitor.shared
    @ObservedObject var sys = SystemMonitor.shared
    @AppStorage("pingHost") private var pingHost = "1.1.1.1"
    @State private var hostDraft = ""

    var body: some View {
        HStack(spacing: 10) {
            Card { networkCard }.frame(width: 236)
            Card { pingCard }.frame(width: 178)
            Card { systemCard }
        }
        .onAppear {
            hostDraft = pingHost
            net.activate()
        }
        .onDisappear { net.deactivate() }
    }

    private var wifiText: String {
        if let s = net.ssid, let r = net.rssi { return "\(s) · \(r) dBm" }
        if let r = net.rssi { return "Connecté · \(r) dBm" }
        return "Non connecté"
    }

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            HStack {
                SectionTitle("Réseau", symbol: "network", tint: .cyan)
                Spacer()
                IconButton(symbol: "arrow.clockwise", size: 9, help: "Actualiser l'IP publique") { net.fetchPublicIP() }
            }
            InfoRow(label: "Wi-Fi", value: wifiText, mono: false)
            if let tx = net.txRate {
                InfoRow(label: "Lien", value: "\(Int(tx)) Mb/s" + (net.channel.map { " · canal \($0)" } ?? ""), mono: false)
            }
            ForEach(net.addresses.prefix(3)) { a in
                InfoRow(label: a.name, value: "\(a.ip)/\(a.prefix)", copyable: true)
            }
            InfoRow(label: "Passerelle", value: net.gateway ?? "—", copyable: true)
            InfoRow(label: "DNS", value: net.dns.isEmpty ? "—" : net.dns.joined(separator: ", "), copyable: true)
            InfoRow(label: "IP publique", value: net.publicIP ?? "…", copyable: true)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Label(fmtBytes(net.down) + "/s", systemImage: "arrow.down.circle.fill").foregroundStyle(.green)
                Label(fmtBytes(net.up) + "/s", systemImage: "arrow.up.circle.fill").foregroundStyle(.orange)
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
        }
    }

    private var pingColor: Color {
        guard let p = net.lastPing else { return .red }
        return p < 40 ? .green : (p < 100 ? .orange : .red)
    }

    private var pingCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionTitle("Ping", symbol: "waveform.path.ecg", tint: .green)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(net.lastPing.map { String(format: "%.0f", $0) } ?? (net.pingHistory.isEmpty ? "…" : "perdu"))
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(pingColor)
                if net.lastPing != nil { Text("ms").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)) }
            }
            PingGraph(values: net.pingHistory).frame(height: 46)
            Text("Perte \(net.lossPercent) %" + (net.averagePing.map { String(format: " · moy. %.0f ms", $0) } ?? ""))
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                TextField("Hôte", text: $hostDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, design: .monospaced))
                    .onSubmit(applyHost)
                Button("OK", action: applyHost).buttonStyle(PillButtonStyle())
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
        }
    }

    private func applyHost() {
        let h = hostDraft.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty, !h.hasPrefix("-") else { return }
        pingHost = h
        net.resetPing()
    }

    private var systemCard: some View {
        let b = sys.battery
        return VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Système", symbol: "cpu", tint: .purple)
            GaugeRow(label: "CPU", value: sys.cpu, text: "\(Int((sys.cpu * 100).rounded())) %",
                     tint: sys.cpu > 0.8 ? .red : .purple)
            GaugeRow(label: "Mémoire", value: sys.memUsed / sys.memTotal,
                     text: "\(fmtBytes(sys.memUsed)) / \(fmtBytes(sys.memTotal))", tint: .blue)
            GaugeRow(label: "Disque", value: 1 - sys.diskFree / sys.diskTotal,
                     text: "\(fmtBytes(sys.diskFree)) libres", tint: .teal)
            if b.present {
                GaugeRow(label: "Batterie", value: Double(b.level) / 100,
                         text: "\(b.level) %" + (b.charging ? " · en charge" : (b.onAC ? " · secteur" : "")),
                         tint: SystemMonitor.color(for: b) == .white ? .green : SystemMonitor.color(for: b))
                Text(batteryDetails(b))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text("Allumé depuis \(fmtDuration(ProcessInfo.processInfo.systemUptime))")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func batteryDetails(_ b: BatteryInfo) -> String {
        var parts: [String] = []
        if let t = b.timeToFull, b.charging { parts.append("pleine dans \(fmtDuration(Double(t) * 60))") }
        if let t = b.timeToEmpty, !b.onAC { parts.append("≈ \(fmtDuration(Double(t) * 60)) restantes") }
        if let h = b.health { parts.append("santé \(h) %") }
        if let c = b.cycles { parts.append("\(c) cycles") }
        if let w = b.adapterWatts { parts.append("chargeur \(w) W") }
        return parts.joined(separator: " · ")
    }
}

struct PingGraph: View {
    let values: [Double?]
    private let slots = 40

    var body: some View {
        GeometryReader { geo in
            let padded: [Double?] = [Double?](repeating: -1, count: max(0, slots - values.count)) + values.suffix(slots)
            let maxV = max(60, values.compactMap { $0 }.max() ?? 60)
            let barW = geo.size.width / CGFloat(slots)
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(padded.enumerated()), id: \.offset) { _, v in
                    bar(v, maxV: maxV, height: geo.size.height)
                        .frame(width: max(1, barW - 1.5))
                        .frame(width: barW, alignment: .center)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
    }

    @ViewBuilder
    private func bar(_ v: Double?, maxV: Double, height: CGFloat) -> some View {
        if let v {
            if v < 0 {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 2)
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(v < 40 ? Color.green : (v < 100 ? Color.orange : Color.red))
                    .frame(height: max(2, CGFloat(v / maxV) * height))
            }
        } else {
            RoundedRectangle(cornerRadius: 1).fill(Color.red.opacity(0.6)).frame(height: height)
        }
    }
}
