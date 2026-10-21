import AppKit
import SwiftUI

struct PanelView: View {
    @EnvironmentObject var m: BoxMonitor
    @State private var showSettings = false

    private var s: Snapshot { m.snap }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !m.isConfigured {
                Card { SetupForm(title: "Connect to your box") }
            }
            if s.reachable {
                batteryCard
                signalCard
                detailSection
            } else if m.isConfigured {
                Text(m.discovering ? "Looking for your box…"
                     : "Can't reach the box at \(m.host). Are you on its Wi-Fi?")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 330)
    }

    // MARK: sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.networkOperator.isEmpty ? "Ooredoo box" : s.networkOperator)
                    .font(.headline)
                Text(statusLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if s.reachable {
                Text(shortNetwork(s.networkType))
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                Image(systemName: "cellularbars", variableValue: Double(s.bars) / 5)
                    .font(.title3)
            }
        }
    }

    private var statusLine: String {
        guard s.reachable else { return "Offline" }
        var bits: [String] = []
        bits.append(s.flightMode ? "Flight mode" : s.connected ? "Connected" : "No data connection")
        if !s.simReady { bits.append("SIM not ready") }
        if let t = m.lastUpdate {
            let age = Date().timeIntervalSince(t)
            bits.append(age < 10 ? "updated just now"
                : "updated \(RelativeDateTimeFormatter().localizedString(for: t, relativeTo: Date()))")
        }
        return bits.joined(separator: " · ")
    }

    private var batteryCard: some View {
        Card {
            HStack(spacing: 12) {
                BatteryGlyph(pct: s.battery ?? 0, charging: s.charging)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.battery.map { "\($0)%" } ?? "No battery")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text(batteryDetail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var batteryDetail: String {
        if s.charging { return "Charging" }
        guard let rate = m.drainPerHour, let b = s.battery else {
            return "On battery · measuring drain…"
        }
        let hours = Double(b) / rate
        return String(format: "%.0f%%/h · about %@ left", rate, formatDuration(hours * 3600))
    }

    private var signalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                if let lte = s.lte { radioRow(title: "LTE", radio: lte, bandPrefix: "B") }
                if let nr = s.nr {
                    Divider()
                    radioRow(title: "5G NR", radio: nr, bandPrefix: "n")
                }
                if !s.cellID.isEmpty {
                    Text("Cell \(s.cellID)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func radioRow(title: String, radio: Radio, bandPrefix: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(bandsText(radio, prefix: bandPrefix))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                Metric(label: "RSRP", value: radio.rsrp.map { "\($0)" }, unit: "dBm",
                       quality: quality(rsrp: radio.rsrp))
                Metric(label: "RSRQ", value: radio.rsrq.map { "\($0)" }, unit: "dB",
                       quality: quality(rsrq: radio.rsrq))
                Metric(label: "SINR", value: radio.sinr.map { "\($0)" }, unit: "dB",
                       quality: quality(sinr: radio.sinr))
            }
        }
    }

    @ViewBuilder private var detailSection: some View {
        switch m.detail {
        case .off:
            EmptyView()
        case .needsSetup:
            EmptyView()
        case .paused(let until, let reason):
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Detailed stats paused").font(.subheadline.weight(.semibold))
                        Text("\(reason) · resumes \(until.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Resume") { m.resumeDetailed() }.controlSize(.small)
                }
            }
            detailCards
        case .error(let msg):
            Card {
                Label(msg, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        case .active:
            detailCards
        }
    }

    @ViewBuilder private var detailCards: some View {
        if s.sessionDL != nil {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 0) {
                        Metric(label: "↓ Download", value: s.dlRate.map(formatRate), unit: nil, quality: nil)
                        Metric(label: "↑ Upload", value: s.ulRate.map(formatRate), unit: nil, quality: nil)
                    }
                    HStack {
                        Text("Session \(formatMB(s.sessionDL)) ↓ · \(formatMB(s.sessionUL)) ↑")
                        Spacer()
                        Text("Month \(formatMB(s.monthTotal))")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            Card {
                HStack(spacing: 0) {
                    Metric(label: "CPU", value: s.cpu.map { String(format: "%.0f", $0) }, unit: "%",
                           quality: s.cpu.map { $0 > 80 ? .poor : $0 > 50 ? .fair : .good })
                    Metric(label: "Temp", value: s.temperature.map { "\($0)" }, unit: "°C",
                           quality: s.temperature.map { $0 > 70 ? .poor : $0 > 58 ? .fair : .good })
                    Metric(label: "Memory", value: s.memoryPct.map { String(format: "%.0f", $0) }, unit: "%",
                           quality: nil)
                    Metric(label: "Uptime", value: s.uptime.map { formatDuration(Double($0)) }, unit: nil,
                           quality: nil)
                }
            }
            clientsCard
            networkModeRow
        }
    }

    private var clientsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("Wi-Fi clients · \(s.clients.count)").font(.subheadline.weight(.semibold))
                ForEach(s.clients) { c in
                    HStack {
                        Text(c.name).lineLimit(1)
                        Spacer()
                        Text(c.band).foregroundStyle(.secondary)
                        if let r = c.rssi {
                            Text("\(r) dBm").monospacedDigit()
                                .foregroundStyle(quality(wifi: r).color)
                        }
                        if let rate = c.rate { Text("\(rate) Mb/s").monospacedDigit().foregroundStyle(.secondary) }
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var networkModeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Network mode").font(.subheadline)
                Spacer()
                Menu(modeLabel(s.networkMode)) {
                    ForEach(s.supportedModes.reversed(), id: \.self) { mode in
                        Button {
                            m.setNetworkMode(mode)
                        } label: {
                            if mode == s.networkMode {
                                Label(modeLabel(mode), systemImage: "checkmark")
                            } else {
                                Text(modeLabel(mode))
                            }
                        }
                    }
                }
                .fixedSize()
                .disabled(s.supportedModes.isEmpty)
            }
            if let msg = m.actionMessage {
                Text(msg).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// The widest supported mode is what the web UI calls "Auto".
    private func modeLabel(_ mode: String?) -> String {
        guard let mode else { return "—" }
        let name = networkModeLabels[mode] ?? mode
        return mode == s.supportedModes.last ? "Auto (\(name))" : name
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showSettings { settings }
            HStack {
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Button {
                    m.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh now")
                Spacer()
                Button("Open web UI") {
                    m.pauseForWebUI()
                    if let url = URL(string: "https://\(m.host)/") { NSWorkspace.shared.open(url) }
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
    }

    private var settings: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                if m.isConfigured {
                    SetupForm(title: "Box login")
                    Divider()
                }
                Toggle("Detailed stats (uses the admin session)", isOn: $m.detailedEnabled)
                    .font(.caption)
                Text("The box allows one login at a time. While detailed stats are on, the web UI and this app take turns: opening the web UI pauses the app for 10 minutes.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if m.isConfigured {
                    Button("Forget saved password", role: .destructive) { m.signOut() }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
        }
    }
}

/// The box is found automatically, so normally only the password is asked for.
/// Address and username live under "Advanced". The login is tried once before anything is saved.
struct SetupForm: View {
    @EnvironmentObject var m: BoxMonitor
    let title: String
    @State private var host = ""
    @State private var user = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @State private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            discoveryStatus
            SecureField(m.isConfigured ? "Password (saved in Keychain)" : "Admin password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                Grid(alignment: .leading, verticalSpacing: 6) {
                    GridRow {
                        Text("Find box").font(.caption).foregroundStyle(.secondary)
                        Toggle("Automatically", isOn: Binding(get: { m.autoDetect }, set: { m.setAutoDetect($0) }))
                            .font(.caption)
                    }
                    if !m.autoDetect {
                        GridRow {
                            Text("Address").font(.caption).foregroundStyle(.secondary)
                            TextField(BoxMonitor.defaultHost, text: $host)
                        }
                    }
                    GridRow {
                        Text("Username").font(.caption).foregroundStyle(.secondary)
                        TextField(BoxMonitor.defaultUser, text: $user)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, 4)
            }
            .font(.caption)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            }
            HStack {
                Text("Checked once, then kept in your Keychain.")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(m.isConfigured ? "Update" : "Connect", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || password.isEmpty)
            }
        }
        .onAppear {
            host = m.host
            user = m.username
        }
        .onChange(of: m.host) { _, new in host = new }
    }

    @ViewBuilder private var discoveryStatus: some View {
        if m.discovering && !m.snap.reachable {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Looking for your box…")
            }
            .font(.caption).foregroundStyle(.secondary)
        } else if m.snap.reachable {
            Label("Found \(m.model ?? "your box") at \(m.host)", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("No box found. Join its Wi-Fi, or set the address under Advanced.",
                      systemImage: "wifi.exclamationmark")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Search again") { Task { await m.discover(force: true) } }
                    .controlSize(.small)
            }
        }
    }

    private func submit() {
        guard !busy, !password.isEmpty else { return }
        busy = true
        error = nil
        Task {
            error = await m.connect(username: user, password: password, manualHost: m.autoDetect ? nil : host)
            busy = false
            if error == nil { password = "" }
        }
    }
}

// MARK: components

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

enum Quality {
    case good, fair, poor
    var color: Color {
        switch self {
        case .good: return .green
        case .fair: return .orange
        case .poor: return .red
        }
    }
}

struct Metric: View {
    let label: String
    let value: String?
    let unit: String?
    let quality: Quality?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if let q = quality {
                    Circle().fill(q.color).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                }
                Text(value ?? "—").font(.system(.body, design: .rounded).weight(.medium)).monospacedDigit()
                if let u = unit, value != nil { Text(u).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BatteryGlyph: View {
    let pct: Int
    let charging: Bool

    var body: some View {
        let symbol = charging ? "battery.100percent.bolt"
            : pct > 87 ? "battery.100percent" : pct > 62 ? "battery.75percent"
            : pct > 37 ? "battery.50percent" : pct > 12 ? "battery.25percent" : "battery.0percent"
        Image(systemName: symbol)
            .font(.system(size: 26))
            .foregroundStyle(charging ? .green : pct <= 20 ? .red : pct <= 40 ? .orange : .primary)
    }
}

// MARK: formatting & thresholds

func quality(rsrp: Int?) -> Quality? {
    guard let v = rsrp else { return nil }
    return v >= -90 ? .good : v >= -105 ? .fair : .poor
}

func quality(rsrq: Int?) -> Quality? {
    guard let v = rsrq else { return nil }
    return v >= -10 ? .good : v >= -15 ? .fair : .poor
}

func quality(sinr: Int?) -> Quality? {
    guard let v = sinr else { return nil }
    return v >= 13 ? .good : v >= 0 ? .fair : .poor
}

func quality(wifi rssi: Int) -> Quality {
    rssi >= -60 ? .good : rssi >= -72 ? .fair : .poor
}

func bandsText(_ r: Radio, prefix: String) -> String {
    let bands = r.bands.split(separator: "+").map { "\(prefix)\($0)" }.joined(separator: "+")
    guard !r.bandwidth.isEmpty else { return bands }
    return "\(bands) · \(r.bandwidth) MHz"
}

func formatRate(_ bytesPerSec: Double) -> String {
    let bits = bytesPerSec * 8
    if bits >= 1_000_000 { return String(format: "%.1f Mb/s", bits / 1_000_000) }
    if bits >= 1_000 { return String(format: "%.0f kb/s", bits / 1_000) }
    return "0 kb/s"
}

func formatMB(_ mb: Double?) -> String {
    guard let mb else { return "—" }
    return mb >= 1000 ? String(format: "%.2f GB", mb / 1000) : String(format: "%.0f MB", mb)
}

func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds)
    let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}
