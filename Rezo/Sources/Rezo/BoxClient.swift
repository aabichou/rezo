import CryptoKit
import Foundation

typealias JSON = [String: Any]

enum BoxError: LocalizedError {
    case noAuth, loginTimeout, limited
    case loginFailed(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noAuth: return "Session taken over"
        case .loginTimeout: return "Session expired"
        case .limited: return "Not allowed for admin"
        case .loginFailed(let m): return m
        case .failed(let m): return m
        }
    }
}

/// Talks to the ZLT X31 web API: every call is a JSON POST to /cgi-bin/http.cgi
/// with a numeric `cmd`. Reads put method "GET" in the body.
final class BoxClient: NSObject, URLSessionDelegate, @unchecked Sendable {
    let host: String
    private let timeout: TimeInterval
    private(set) var sessionId = ""
    private var token = ""

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = timeout + 4
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    init(host: String, timeout: TimeInterval = 6) {
        self.host = host
        self.timeout = timeout
    }

    /// The model name if this host answers like a ZLT box, else nil.
    func identify() async -> String? {
        guard let r = try? await get(113, auth: false), r["network_type_str"] != nil else { return nil }
        let model = r.str("board_type")
        return model.isEmpty ? "5G box" : model
    }

    var hasSession: Bool { !sessionId.isEmpty }

    func dropSession() {
        sessionId = ""
        token = ""
    }

    // The box ships a self-signed certificate; trust it for this host only.
    func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           space.host == host, let trust = space.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }

    private func call(_ body: JSON) async throws -> JSON {
        var req = URLRequest(url: URL(string: "https://\(host)/cgi-bin/http.cgi")!)
        req.httpMethod = "POST"
        req.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? JSON) ?? [:]
    }

    private func check(_ r: JSON) throws {
        guard (r["success"] as? Bool) == false, let m = r["message"] as? String else { return }
        switch m {
        case "NO_AUTH": throw BoxError.noAuth
        case "LOGIN_TIMEOUT": throw BoxError.loginTimeout
        case "LIMITED_ACCESS": throw BoxError.limited
        default: throw BoxError.failed(m)
        }
    }

    /// passwd = sha256(token + password). The box keeps ONE session: this logs
    /// out any open browser tab, and a browser login logs this out.
    func login(user: String, password: String) async throws {
        let t = try await call(["cmd": 232, "method": "GET", "sessionId": ""])
        guard let tok = t["token"] as? String else { throw BoxError.failed("No login token") }
        let hash = SHA256.hash(data: Data((tok + password).utf8))
            .map { String(format: "%02x", $0) }.joined()
        let r = try await call([
            "cmd": 100, "method": "POST", "sessionId": "",
            "username": user, "passwd": hash, "token": tok, "isAutoUpgrade": "0",
        ])
        guard (r["success"] as? Bool) == true, let sid = r["sessionId"] as? String, !sid.isEmpty else {
            if (r["login_fail2"] as? String) == "fail" {
                throw BoxError.loginFailed("Locked out after failed attempts, try later")
            }
            throw BoxError.loginFailed("Wrong password")
        }
        sessionId = sid
        token = tok
    }

    func get(_ cmd: Int, auth: Bool = true, _ params: JSON = [:]) async throws -> JSON {
        var body: JSON = ["cmd": cmd, "method": "GET", "sessionId": auth ? sessionId : ""]
        body.merge(params) { $1 }
        let r = try await call(body)
        try check(r)
        return r
    }

    func post(_ cmd: Int, _ params: JSON = [:]) async throws -> JSON {
        var body: JSON = ["cmd": cmd, "method": "POST", "sessionId": sessionId, "token": token]
        body.merge(params) { $1 }
        let r = try await call(body)
        try check(r)
        return r
    }
}

extension Dictionary where Key == String, Value == Any {
    func str(_ k: String) -> String { (self[k] as? String) ?? "" }
    func int(_ k: String) -> Int? { Int(str(k).trimmingCharacters(in: .whitespaces)) }
    func double(_ k: String) -> Double? { Double(str(k).trimmingCharacters(in: .whitespaces)) }
}
