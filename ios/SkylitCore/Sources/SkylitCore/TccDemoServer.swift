import Foundation

public final class FakeTccServer: TccTransport, @unchecked Sendable {
    public struct Call: Sendable {
        public let method: String
        public let url: URL
        public let headers: [String: String]
        public let body: Data?

        public var path: String { url.path }
        public var text: String { body.map { String(decoding: $0, as: UTF8.self) } ?? "" }
        public var json: [String: Any]? {
            body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }

    public enum LoginBehavior: Sendable {
        case normal
        case emptyCookie
        case tooManyAttempts
        case unauthorized
        case redirect(String)
    }

    public enum Glitch: Sendable {
        case status(Int)
        case redirect(String)
        case html
        case oversized
    }

    public static let demoCredentials = TccCredentials(username: "home@example.com", password: "demo-password")

    private let lock = NSLock()
    private var recorded: [Call] = []
    private var sessions: Set<String> = []
    private var issued = 0
    private var glitches: [Glitch] = []
    private var behavior = LoginBehavior.normal
    private var unreachable = false
    private var rejectsWrites = false
    private var account: TccCredentials
    private var locationId = 4242
    private var order: [Int] = []
    private var names: [Int: String] = [:]
    private var payloads: [Int: [String: Any]] = [:]

    public init(account: TccCredentials = FakeTccServer.demoCredentials) {
        self.account = account
    }

    public var calls: [Call] { lock.withLock { recorded } }
    public var loginCount: Int { calls.filter { $0.method == "POST" && $0.path == "/portal" }.count }
    public var writes: [Call] { calls.filter { $0.path.hasSuffix("SubmitControlScreenChanges") } }
    public var reads: [Call] { calls.filter { $0.path.contains("CheckDataSession") } }

    public func setLogin(_ next: LoginBehavior) { lock.withLock { behavior = next } }
    public func setUnreachable(_ value: Bool) { lock.withLock { unreachable = value } }
    public func setRejectsWrites(_ value: Bool) { lock.withLock { rejectsWrites = value } }
    public func queue(_ glitch: Glitch, count: Int = 1) { lock.withLock { glitches += Array(repeating: glitch, count: count) } }
    public func expireSessions() { lock.withLock { sessions = [] } }
    public func setPassword(_ password: String) { lock.withLock { account = TccCredentials(username: account.username, password: password) } }

    public func addThermostat(id: Int, name: String, ui: [String: Any], fan: [String: Any]? = ["fanMode": 0, "fanIsRunning": false]) {
        var latest: [String: Any] = ["uiData": ui, "hasFan": fan != nil, "drData": [String: Any]()]
        if let fan { latest["fanData"] = fan }
        lock.withLock {
            order.append(id)
            names[id] = name
            payloads[id] = ["success": true, "deviceLive": true, "communicationLost": false, "latestData": latest]
        }
    }

    public func update(_ id: Int, _ change: (inout [String: Any]) -> Void) {
        lock.withLock {
            guard var payload = payloads[id] else { return }
            change(&payload)
            payloads[id] = payload
        }
    }

    public func updateUI(_ id: Int, _ values: [String: Any]) {
        update(id) { payload in
            guard var latest = payload["latestData"] as? [String: Any], var ui = latest["uiData"] as? [String: Any] else { return }
            ui.merge(values) { _, new in new }
            latest["uiData"] = ui
            payload["latestData"] = latest
        }
    }

    public func ui(_ id: Int) -> [String: Any] {
        lock.withLock { ((payloads[id]?["latestData"] as? [String: Any])?["uiData"] as? [String: Any]) ?? [:] }
    }

    public static func ui(mode: Int, indoor: Double, heat: Double, cool: Double, status: Int, nextPeriod: Int = 72, units: String = "F",
                          running: Any = NSNull()) -> [String: Any] {
        let celsius = units == "C"
        return ["DispTemperature": indoor, "DisplayUnits": units, "HeatSetpoint": heat, "CoolSetpoint": cool,
                "HeatLowerSetptLimit": celsius ? 4.5 : 40, "HeatUpperSetptLimit": celsius ? 32 : 90,
                "CoolLowerSetptLimit": celsius ? 10 : 50, "CoolUpperSetptLimit": celsius ? 37 : 99, "Deadband": 0,
                "SystemSwitchPosition": mode, "SwitchHeatAllowed": true, "SwitchCoolAllowed": true, "SwitchOffAllowed": true,
                "SwitchAutoAllowed": false, "SwitchEmergencyHeatAllowed": false,
                "StatusHeat": status, "StatusCool": status, "HeatNextPeriod": nextPeriod, "CoolNextPeriod": nextPeriod,
                "EquipmentOutputStatus": running, "IndoorHumidity": 41, "IndoorHumiditySensorAvailable": true,
                "IndoorHumiditySensorNotFault": true, "OutdoorTemperature": 58, "OutdoorTemperatureAvailable": true,
                "OutdoorHumidity": 62, "OutdoorHumidityAvailable": true]
    }

    public static func sample() -> FakeTccServer {
        let server = FakeTccServer()
        server.addThermostat(id: 1001, name: "Level-0", ui: ui(mode: 1, indoor: 69, heat: 70, cool: 78, status: 2, running: 1),
                             fan: ["fanMode": 0, "fanIsRunning": true])
        server.addThermostat(id: 1002, name: "level-1", ui: ui(mode: 3, indoor: 74, heat: 62, cool: 76, status: 1, running: 0))
        return server
    }

    public func send(_ request: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        let call = Call(method: request.httpMethod ?? "GET", url: url, headers: request.allHTTPHeaderFields ?? [:], body: body)
        return try lock.withLock {
            recorded.append(call)
            if unreachable { throw URLError(.notConnectedToInternet) }
            let (status, headers, payload) = answer(call)
            return (payload, HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
        }
    }

    private typealias Answer = (Int, [String: String], Data)

    private func html(_ status: Int, _ text: String, _ extra: [String: String] = [:]) -> Answer {
        (status, extra.merging(["Content-Type": "text/html; charset=utf-8"]) { old, _ in old }, Data(text.utf8))
    }

    private func json(_ value: Any) -> Answer {
        (200, ["Content-Type": "application/json; charset=utf-8"], (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])) ?? Data())
    }

    private func isSignedIn(_ call: Call) -> Bool {
        let header = call.headers["Cookie"] ?? ""
        return header.components(separatedBy: "; ").contains { pair in
            pair.hasPrefix(TccClient.authCookie + "=") && sessions.contains(String(pair.dropFirst(TccClient.authCookie.count + 1)))
        }
    }

    private func answer(_ call: Call) -> Answer {
        let path = call.path
        if call.method == "POST", path == "/portal" { return login(call) }
        if case .redirect(let location) = behavior, call.method == "GET", location.hasPrefix("/portal/"), location.hasPrefix(path) {
            return html(302, "", ["Location": location])
        }
        if call.method == "GET", path == "/portal" {
            if case .emptyCookie = behavior {
                return html(200, "<html>Sign in</html>", ["Set-Cookie": "\(TccClient.authCookie)=; expires=Mon, 11-Oct-1999 22:00:00 GMT; path=/"])
            }
            return isSignedIn(call) ? html(302, "", ["Location": "/portal/\(locationId)/Zones"]) : html(401, "")
        }
        if call.method == "GET", path == "/portal/\(locationId)/Zones" {
            return isSignedIn(call) ? html(200, "<html>Zones</html>") : html(401, "")
        }
        if call.method == "POST", path == "/portal/Account/LogOff" {
            sessions = []
            return html(200, "")
        }
        if !glitches.isEmpty {
            switch glitches.removeFirst() {
            case .status(let status): return html(status, "<html>Error</html>")
            case .redirect(let location): return html(302, "", ["Location": location])
            case .html: return html(200, "<html>Maintenance</html>")
            case .oversized: return (200, ["Content-Type": "application/json"], Data(count: TccClient.maxBody + 1))
            }
        }
        guard isSignedIn(call) else { return html(401, "") }
        let refreshed = ["Set-Cookie": "\(TccClient.authCookie)=\(sessions.first ?? ""); expires=Sun, 11-Oct-2026 25:61:00 GMT; path=/; secure; HttpOnly"]
        if call.method == "POST", path == "/portal/Location/GetLocationListData" {
            let page = URLComponents(url: call.url, resolvingAgainstBaseURL: true)?.queryItems?.first { $0.name == "page" }?.value
            let devices = order.map { ["DeviceID": $0, "Name": names[$0] ?? "", "MacID": String(format: "00D02D%06X", $0)] as [String: Any] }
            return json(page == "1" ? [["LocationID": locationId, "Devices": devices] as [String: Any]] : [])
        }
        if call.method == "GET", path.hasPrefix("/portal/Device/CheckDataSession/"), let id = Int(call.url.lastPathComponent), let payload = payloads[id] {
            var reply = json(payload)
            reply.1.merge(refreshed) { old, _ in old }
            return reply
        }
        if call.method == "POST", path == "/portal/Device/SubmitControlScreenChanges", let change = call.json,
           let id = (change["DeviceID"] as? NSNumber)?.intValue, var payload = payloads[id],
           var latest = payload["latestData"] as? [String: Any], var ui = latest["uiData"] as? [String: Any] {
            if rejectsWrites { return json(["success": 0]) }
            for key in ["HeatSetpoint", "CoolSetpoint", "StatusHeat", "StatusCool", "HeatNextPeriod", "CoolNextPeriod"] {
                if let value = change[key], !(value is NSNull) { ui[key] = value }
            }
            if let position = change["SystemSwitch"], !(position is NSNull) { ui["SystemSwitchPosition"] = position }
            latest["uiData"] = ui
            payload["latestData"] = latest
            payloads[id] = payload
            return json(["success": 1])
        }
        return html(404, "")
    }

    private func login(_ call: Call) -> Answer {
        var fields: [String: String] = [:]
        for pair in call.text.components(separatedBy: "&") {
            let parts = pair.components(separatedBy: "=")
            if parts.count == 2 { fields[parts[0]] = parts[1].removingPercentEncoding }
        }
        switch behavior {
        case .tooManyAttempts: return html(302, "", ["Location": "/portal/Account/TooManyAttempts"])
        case .unauthorized: return html(401, "")
        case .redirect(let location): return html(302, "", ["Location": location])
        case .emptyCookie: return html(200, "<html>Sign in</html>")
        case .normal: break
        }
        guard fields["UserName"] == account.username, fields["Password"] == account.password else {
            return html(200, "<html><div class=\"validation-summary-errors\">The email or password provided is incorrect.</div></html>")
        }
        issued += 1
        let token = "SESSION\(issued)"
        sessions = [token]
        let cookies = "\(TccClient.authCookie)=\(token); expires=Sun, 11-Oct-2026 25:61:00 GMT; path=/; secure; HttpOnly, "
            + "ASP.NET_SessionId=abc\(issued); path=/; HttpOnly, thlang=en-US; expires=Mon, 11-Oct-2027 18:00:00 GMT; path=/"
        return html(302, "", ["Location": "/portal/", "Set-Cookie": cookies])
    }
}
