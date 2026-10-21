import Foundation
import SwiftUI

struct Radio {
    var rsrp: Int?
    var rsrq: Int?
    var sinr: Int?
    var bands = ""
    var bandwidth = ""
    var pci = ""
}

struct WifiClient: Identifiable {
    var id: String { mac }
    var mac = ""
    var name = ""
    var band = ""
    var rssi: Int?
    var rate: Int?
}

struct Snapshot {
    var reachable = false
    var networkType = ""
    var networkOperator = ""
    var bars = 0
    var connected = false
    var simReady = false
    var flightMode = false
    var battery: Int?
    var charging = false
    var lte: Radio?
    var nr: Radio?
    var cellID = ""
    var wanIP = ""

    // Login-only fields, nil until the detailed loop has run.
    var cpu: Double?
    var temperature: Int?
    var memoryPct: Double?
    var uptime: Int?
    var dlRate: Double?  // bytes/s
    var ulRate: Double?
    var sessionDL: Double?  // MB
    var sessionUL: Double?
    var monthTotal: Double?
    var clients: [WifiClient] = []
    var networkMode: String?
    var supportedModes: [String] = []
}

enum DetailState: Equatable {
    case off
    case needsSetup
    case active
    case paused(until: Date, reason: String)
    case error(String)
}

/// cmd 256 `networkMode` values, as labelled by the web UI.
let networkModeLabels: [String: String] = [
    "1": "2G only", "2": "3G only", "3": "3G/2G", "4": "4G only", "6": "4G/3G", "7": "4G/3G/2G",
    "C": "5G NSA only", "10": "5G SA only", "14": "5G SA/4G", "1C": "5G (SA+NSA)/4G",
    "1E": "5G/4G/3G", "1F": "5G/4G/3G/2G",
]

/// Modes the web UI offers for each `display_mode` capability value.
private func supportedModes(displayMode: String) -> [String] {
    switch displayMode.uppercased() {
    case "0": return []
    case "3": return ["1", "2", "3"]
    case "6": return ["2", "4", "6"]
    case "7": return ["1", "2", "4", "7"]
    case "14": return ["4", "10", "14"]
    case "1C": return ["4", "C", "10", "1C"]
    case "1E": return ["2", "4", "6", "C", "10", "1C", "1E"]
    case "1F": return ["4", "7", "C", "10", "1C", "1F"]
    default: return ["4", "C", "10", "1C"]
    }
}

@MainActor
final class BoxMonitor: ObservableObject {
    static let defaultHost = "192.168.100.1"
    static let defaultUser = "admin"

    @Published private(set) var snap = Snapshot()
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var detail: DetailState = .off
    @Published private(set) var drainPerHour: Double?
    @Published private(set) var actionMessage: String?
    @Published private(set) var host: String
    @Published private(set) var username: String
    @Published private(set) var isConfigured: Bool
    @Published private(set) var autoDetect: Bool
    @Published private(set) var discovering = false
    @Published private(set) var model: String?
    @Published var detailedEnabled: Bool {
        didSet {
            UserDefaults.standard.set(detailedEnabled, forKey: "detailedEnabled")
            if detailedEnabled { kickDetailed() } else { detail = .off }
        }
    }

    private(set) var client: BoxClient
    private var batterySamples: [(at: Date, pct: Int)] = []
    private var lastFlow: (at: Date, dl: Double, ul: Double)?
    private var fastTask: Task<Void, Never>?
    private var slowTask: Task<Void, Never>?
    private var failedPolls = 0
    private var lastDiscovery: Date?

    // Unauthenticated status is cheap; detailed polling holds the single session.
    private let fastInterval: Duration = .seconds(15)
    private let slowInterval: Duration = .seconds(30)
    private let takeoverPause: TimeInterval = 5 * 60

    init() {
        let d = UserDefaults.standard
        let host = d.string(forKey: "host") ?? Self.defaultHost
        self.host = host
        username = d.string(forKey: "username") ?? Self.defaultUser
        detailedEnabled = d.object(forKey: "detailedEnabled") as? Bool ?? true
        autoDetect = d.object(forKey: "autoDetect") as? Bool ?? true
        isConfigured = Keychain.load() != nil
        client = BoxClient(host: host)
        start()
        if autoDetect { Task { await discover(force: true) } }
    }

    /// Looks for the box (gateway first, then common addresses) and switches to it.
    func discover(force: Bool = false) async {
        guard !discovering else { return }
        if !force, let t = lastDiscovery, Date().timeIntervalSince(t) < 30 { return }
        discovering = true
        lastDiscovery = Date()
        defer { discovering = false }
        guard let found = await Discovery.find(saved: host) else { return }
        model = found.model
        if found.host != host { useHost(found.host) }
    }

    func setAutoDetect(_ on: Bool) {
        autoDetect = on
        UserDefaults.standard.set(on, forKey: "autoDetect")
        if on { Task { await discover(force: true) } }
    }

    private func useHost(_ newHost: String) {
        host = newHost
        UserDefaults.standard.set(newHost, forKey: "host")
        client = BoxClient(host: newHost)
        resetReadings()
        refreshNow()
    }

    func start() {
        fastTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollFast()
                try? await Task.sleep(for: self?.fastInterval ?? .seconds(15))
            }
        }
        kickDetailed()
    }

    private func kickDetailed() {
        slowTask?.cancel()
        slowTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollDetailed()
                try? await Task.sleep(for: self?.slowInterval ?? .seconds(30))
            }
        }
    }

    private var password: String? { Keychain.load() }

    /// Tries the credentials once before caching them: the box locks the
    /// account after a few wrong passwords, so a typo must not be retried in a loop.
    /// `manualHost` pins an address and turns auto-detection off; nil keeps the detected one.
    func connect(username rawUser: String, password: String, manualHost: String?) async -> String? {
        let newHost = (manualHost ?? host).trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let newUser = rawUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultUser : rawUser.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newHost.isEmpty, !password.isEmpty else {
            return "Enter the box address and password"
        }
        let candidate = BoxClient(host: newHost)
        do {
            try await candidate.login(user: newUser, password: password)
        } catch let e as BoxError {
            return e.localizedDescription
        } catch {
            return "Can't reach \(newHost)"
        }
        Keychain.save(password)
        if manualHost != nil { setAutoDetect(false) }
        UserDefaults.standard.set(newHost, forKey: "host")
        UserDefaults.standard.set(newUser, forKey: "username")
        let moved = newHost != host
        host = newHost
        username = newUser
        client = candidate
        isConfigured = true
        if moved { resetReadings() }
        detail = .active
        refreshNow()
        kickDetailed()
        return nil
    }

    func signOut() {
        Keychain.delete()
        client.dropSession()
        isConfigured = false
        detail = .needsSetup
        resetReadings()
    }

    private func resetReadings() {
        snap = Snapshot()
        lastUpdate = nil
        lastFlow = nil
        batterySamples.removeAll()
        drainPerHour = nil
    }

    func resumeDetailed() {
        detail = .active
        kickDetailed()
    }

    /// Opening the web UI would fight us for the session, so step aside.
    func pauseForWebUI() {
        client.dropSession()
        detail = .paused(until: Date().addingTimeInterval(10 * 60), reason: "Web UI open")
    }

    func refreshNow() {
        Task {
            await pollFast()
            await pollDetailed()
        }
    }

    // MARK: polling

    private func pollFast() async {
        // Results from a client replaced mid-flight (box moved) are stale.
        let c = client
        do {
            async let s = c.get(113, auth: false)
            async let r = c.get(133, auth: false)
            let (sys, router) = try await (s, r)
            guard c === client else { return }
            var n = snap
            n.reachable = true
            n.networkType = sys.str("network_type_str")
            n.networkOperator = sys.str("network_operator")
            n.bars = sys.int("signal_lvl") ?? 0
            n.connected = sys.str("network_status") == "1"
            n.simReady = sys.str("sim_status") == "1"
            n.flightMode = sys.str("flightMode") == "1"
            n.battery = sys.str("batteryExist") == "1" ? sys.int("batteryCapacity") : nil
            n.charging = ["1", "2"].contains(sys.str("batteryCharge"))
            n.lte = Radio(
                rsrp: router.int("RSRP"), rsrq: router.int("RSRQ"), sinr: router.int("SINR"),
                bands: router.str("currentband"), bandwidth: router.str("bandwidth"), pci: router.str("PCI"))
            if n.networkType.contains("5G"), router.int("RSRP_5G") != nil {
                n.nr = Radio(
                    rsrp: router.int("RSRP_5G"), rsrq: router.int("RSRQ_5G"), sinr: router.int("SINR_5G"),
                    bands: router.str("currentband_5g"), bandwidth: router.str("bandwidth_5g"),
                    pci: router.str("PCI_5G"))
            } else {
                n.nr = nil
            }
            n.cellID = router.str("CELL_ID")
            n.wanIP = router.str("wan_ip")
            snap = n
            lastUpdate = Date()
            failedPolls = 0
            if !sys.str("board_type").isEmpty { model = sys.str("board_type") }
            trackBattery(n)
        } catch {
            guard c === client else { return }
            snap.reachable = false
            failedPolls += 1
            // The box may have moved (new subnet) or we're on another network.
            if autoDetect, failedPolls >= 2 { await discover() }
        }
    }

    private func trackBattery(_ s: Snapshot) {
        guard let pct = s.battery else { return }
        if s.charging {
            batterySamples.removeAll()
            drainPerHour = nil
            return
        }
        let now = Date()
        if batterySamples.last?.pct != pct { batterySamples.append((now, pct)) }
        batterySamples.removeAll { now.timeIntervalSince($0.at) > 90 * 60 }
        // Percent steps are coarse; wait for 10 min and 2 points of drop before estimating.
        guard let first = batterySamples.first else { return }
        let hours = now.timeIntervalSince(first.at) / 3600
        let drop = first.pct - pct
        drainPerHour = (hours >= 1.0 / 6 && drop >= 2) ? Double(drop) / hours : nil
    }

    private func pollDetailed() async {
        guard detailedEnabled else { detail = .off; return }
        guard let pw = password else { detail = .needsSetup; return }
        guard snap.reachable || lastUpdate == nil else { return }
        if case .paused(let until, _) = detail, Date() < until { return }
        do {
            if !client.hasSession { try await client.login(user: username, password: pw) }
            try await fetchDetailed()
            detail = .active
        } catch BoxError.noAuth {
            // Our session was valid and now isn't: someone logged in elsewhere.
            client.dropSession()
            detail = .paused(until: Date().addingTimeInterval(takeoverPause), reason: "Web UI took the session")
        } catch BoxError.loginTimeout {
            client.dropSession()
        } catch BoxError.loginFailed(let msg) {
            // Stop retrying: repeated failures lock the account.
            client.dropSession()
            detail = .error("\(msg). Update the password in Settings.")
            slowTask?.cancel()
        } catch {
            client.dropSession()
            detail = .error(error.localizedDescription)
        }
    }

    private func fetchDetailed() async throws {
        let wan = try await client.get(1002)
        let dev = try await client.get(1001)
        let list = try await client.get(1000)
        let mode = try await client.get(256)

        var n = snap
        n.cpu = dev.double("cpu_usage")
        n.temperature = dev.int("device_temperature")
        n.uptime = dev.int("uptime")
        let mem = dev.str("memory").split(separator: ",").compactMap {
            Double($0.replacingOccurrences(of: "kB", with: "").trimmingCharacters(in: .whitespaces))
        }
        if mem.count >= 3, mem[0] > 0 { n.memoryPct = (mem[0] - mem[1] - mem[2]) / mem[0] * 100 }

        // flow_dl/flow_ul are session MB with 2 decimals; their deltas give throughput.
        let now = Date()
        if let dl = wan.double("flow_dl"), let ul = wan.double("flow_ul") {
            if let last = lastFlow, dl >= last.dl, ul >= last.ul {
                let dt = now.timeIntervalSince(last.at)
                if dt > 1 {
                    n.dlRate = (dl - last.dl) * 1_000_000 / dt
                    n.ulRate = (ul - last.ul) * 1_000_000 / dt
                }
            }
            lastFlow = (now, dl, ul)
            n.sessionDL = dl
            n.sessionUL = ul
        }
        n.monthTotal = wan.double("mon_total_flow")

        var clients: [WifiClient] = []
        for (key, band) in [("wlan5g_wifi_info", "5G"), ("wlan24g_wifi_info", "2.4G")] {
            for c in (list[key] as? [JSON]) ?? [] {
                clients.append(WifiClient(
                    mac: c.str("mac"), name: c.str("user").isEmpty ? c.str("mac") : c.str("user"),
                    band: band, rssi: c.int("rssi"), rate: c.int("txrate")))
            }
        }
        n.clients = clients
        n.networkMode = mode.str("networkMode").uppercased()
        n.supportedModes = supportedModes(displayMode: mode.str("display_mode"))
        snap = n
    }

    // MARK: actions

    func setNetworkMode(_ value: String) {
        Task {
            guard let pw = password else { return }
            actionMessage = "Switching… (≈10 s offline)"
            do {
                if !client.hasSession { try await client.login(user: username, password: pw) }
                do {
                    _ = try await client.post(256, ["networkMode": value])
                } catch BoxError.noAuth {
                    try await client.login(user: username, password: pw)
                    _ = try await client.post(256, ["networkMode": value])
                }
                snap.networkMode = value
                lastFlow = nil
                detail = .active
                actionMessage = nil
                try? await Task.sleep(for: .seconds(10))
                refreshNow()
            } catch {
                actionMessage = "Failed: \(error.localizedDescription)"
            }
        }
    }
}
