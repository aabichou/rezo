import Foundation
import SystemConfiguration

/// Finds the box without asking the user: it is normally the default gateway,
/// and it answers cmd 113 without a login.
enum Discovery {
    static let commonHosts = ["192.168.100.1", "192.168.0.1", "192.168.1.1", "192.168.8.1", "192.168.10.1"]

    static func gateway() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "BoxBar" as CFString, nil, nil),
              let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return ipv4["Router"] as? String
    }

    /// Probes the candidates in parallel and returns the highest-priority one
    /// that looks like a box, with its model name.
    static func find(saved: String?) async -> (host: String, model: String)? {
        var candidates: [String] = []
        for h in [gateway(), saved].compactMap({ $0 }) + commonHosts where !candidates.contains(h) {
            candidates.append(h)
        }
        let hits = await withTaskGroup(of: (Int, String?).self) { group in
            for (i, h) in candidates.enumerated() {
                group.addTask { (i, await BoxClient(host: h, timeout: 2.5).identify()) }
            }
            var found: [Int: String] = [:]
            for await (i, model) in group {
                if let model { found[i] = model }
            }
            return found
        }
        guard let best = hits.keys.min(), let model = hits[best] else { return nil }
        return (candidates[best], model)
    }
}
