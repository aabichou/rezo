import AppKit
import SwiftUI

@main
struct RezoApp: App {
    @StateObject private var monitor = BoxMonitor()

    init() {
        // `Rezo --snapshot <dir>`: render the README screenshots and exit.
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot") {
            let args = CommandLine.arguments
            Screenshots.render(to: i + 1 < args.count ? args[i + 1] : ".")
            exit(0)
        }
        // `Rezo --check`: poll for a few seconds, print what the panel would show, exit.
        if CommandLine.arguments.contains("--check") {
            let m = BoxMonitor()
            let end = Date().addingTimeInterval(8)
            while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
            dump(m.snap)
            print("host:", m.host, "model:", m.model ?? "-", "auto-detect:", m.autoDetect)
            print("detail:", m.detail)
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(monitor)
        } label: {
            MenuBarLabel(snap: monitor.snap)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let snap: Snapshot

    var body: some View {
        if !snap.reachable {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
        } else {
            HStack(spacing: 3) {
                Image(systemName: "cellularbars", variableValue: Double(snap.bars) / 5)
                Text(text)
            }
        }
    }

    private var text: String {
        var parts = [shortNetwork(snap.networkType)]
        if let b = snap.battery { parts.append("\(snap.charging ? "⚡" : "")\(b)%") }
        return parts.joined(separator: " ")
    }
}

func shortNetwork(_ s: String) -> String {
    if s.isEmpty { return "—" }
    if s.hasPrefix("5G") { return s.contains("NSA") ? "5G" : "5G SA" }
    return s
}
