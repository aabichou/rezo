import AppKit
import SwiftUI

/// `Rezo --snapshot <dir>` renders the README screenshots (light and dark) from
/// fixed sample readings, so they never contain a real cell ID, IP or device name.
enum Screenshots {
    static let sample: Snapshot = {
        var s = Snapshot()
        s.reachable = true
        s.networkType = "5G+(NSA)"
        s.networkOperator = "Ooredoo TN"
        s.bars = 5
        s.connected = true
        s.simReady = true
        s.battery = 72
        s.lte = Radio(rsrp: -84, rsrq: -11, sinr: 15, bands: "20+3+1", bandwidth: "10+20+20", pci: "")
        s.nr = Radio(rsrp: -81, rsrq: -11, sinr: 27, bands: "78", bandwidth: "100", pci: "")
        s.cpu = 21
        s.temperature = 47
        s.memoryPct = 74
        s.uptime = 85_000
        s.dlRate = 6_400_000
        s.ulRate = 890_000
        s.sessionDL = 2004
        s.sessionUL = 129
        s.monthTotal = 19_630
        s.clients = [
            WifiClient(mac: "a", name: "MacBook Pro", band: "5G", rssi: -36, rate: 150),
            WifiClient(mac: "b", name: "iPhone", band: "5G", rssi: -44, rate: 150),
            WifiClient(mac: "c", name: "Smart TV", band: "2.4G", rssi: -63, rate: 72),
        ]
        s.networkMode = "1E"
        s.supportedModes = ["2", "4", "6", "C", "10", "1C", "1E"]
        return s
    }()

    @MainActor
    static func render(to dir: String) {
        for (name, look) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let monitor = BoxMonitor(preview: sample, drainPerHour: 13, model: "ZLT X31")
            let view = NSHostingView(rootView: Scene().environmentObject(monitor))
            view.appearance = NSAppearance(named: look)
            let size = view.fittingSize
            view.frame = CGRect(origin: .zero, size: size)

            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: look)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))

            // Draw at 2x for Retina displays.
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = URL(fileURLWithPath: dir).appendingPathComponent("screenshot-\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("wrote \(url.path)")
        }
    }

    /// A slice of menu bar with the Rezo item, and the open panel below it.
    private struct Scene: View {
        @EnvironmentObject var m: BoxMonitor

        var body: some View {
            VStack(alignment: .trailing, spacing: 6) {
                HStack {
                    Spacer()
                    MenuBarLabel(snap: m.snap)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.12)))
                }
                .padding(.horizontal, 10)
                .frame(width: 400, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
                PanelView()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12)))
            }
            .padding(16)
        }
    }
}
