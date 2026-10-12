import Foundation

public protocol TccTransport: Sendable {
    func send(_ request: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse)
}

public actor TccClient {
    public static let origin = URL(string: "https://mytotalconnectcomfort.com")!
    public static let authCookie = ".ASPXAUTH_TRUEHOME"
    public static let reloginInterval: TimeInterval = 600
    public static let maxBody = 1 << 20
    static let maxRedirects = 5
    static let guardKey = "skylit.tcc.loginGuard"

    private enum LoginSignal: Error {
        case throttled
    }

    private let transport: TccTransport
    private let defaults: UserDefaults?
    private let now: @Sendable () -> Date
    private var credentials: TccCredentials?
    private var cookies: [String: String] = [:]
    private var sawEmptyAuthCookie = false
    private var lastLogin: Date?
    private var loginTask: Task<Void, Error>?
    private var counter: Int
    public private(set) var loginGuard: TccLoginGuard

    public init(transport: TccTransport, defaults: UserDefaults? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.defaults = defaults
        self.now = now
        counter = Int(now().timeIntervalSince1970 * 1000)
        loginGuard = defaults?.data(forKey: Self.guardKey).flatMap { try? JSONDecoder().decode(TccLoginGuard.self, from: $0) } ?? TccLoginGuard()
    }

    public var hasSession: Bool { cookies[Self.authCookie] != nil }

    public var session: TccSession? {
        hasSession ? TccSession(cookies: cookies, lastLogin: lastLogin) : nil
    }

    public func setCredentials(_ value: TccCredentials?) {
        credentials = value
        cookies = [:]
    }

    public func restore(_ saved: TccSession) {
        cookies = saved.cookies
        lastLogin = saved.lastLogin
    }

    public func signIn(_ value: TccCredentials) async throws {
        credentials = value
        try await login(automatic: false)
    }

    public func signOut() async {
        if hasSession, let request = try? request("POST", "/portal/Account/LogOff") {
            _ = try? await send(request, body: nil)
        }
        credentials = nil
        cookies = [:]
        lastLogin = nil
    }

    public func locations() async throws -> [TccLocation] {
        try await authorized {
            var found: [TccLocation] = []
            for page in 1...4 {
                let listed: Any
                do {
                    listed = try await self.json("POST", "/portal/Location/GetLocationListData/?page=\(page)&filter=", body: nil)
                } catch TccError.unexpectedResponse where page > 1 {
                    break
                }
                guard let raw = listed as? [[String: Any]], !raw.isEmpty else { break }
                found += raw.compactMap(TccLocation.init)
            }
            return found
        }
    }

    public func thermostat(_ device: TccDevice) async throws -> TccThermostat {
        try await authorized {
            self.counter += 1
            let payload = try await self.json("GET", "/portal/Device/CheckDataSession/\(device.id)?_=\(self.counter)", body: nil)
            guard let object = payload as? [String: Any] else { throw TccError.unexpectedResponse }
            return TccThermostat(device: device, payload: object)
        }
    }

    public func apply(_ change: TccChange) async throws {
        let body = try JSONEncoder().encode(change)
        try await authorized {
            let answer = try await self.json("POST", "/portal/Device/SubmitControlScreenChanges", body: body)
            guard ((answer as? [String: Any])?["success"] as? NSNumber)?.intValue == 1 else { throw TccError.rejected }
        }
    }

    public func setSetpoint(_ which: TccSetpoint, to value: Double, on thermostat: TccThermostat, hold: TccHoldKind = .untilNextPeriod) async throws {
        try await apply(thermostat.setpointChange(which, to: value, hold: hold))
    }

    public func setMode(_ mode: TccMode, on thermostat: TccThermostat) async throws {
        try await apply(thermostat.modeChange(mode))
    }

    public func resumeSchedule(on thermostat: TccThermostat) async throws {
        try await apply(thermostat.resumeChange())
    }

    private func authorized<T>(_ work: () async throws -> T) async throws -> T {
        if !hasSession { try await login(automatic: true) }
        do {
            return try await work()
        } catch TccError.sessionExpired {
            try await login(automatic: true)
            return try await work()
        }
    }

    private func login(automatic: Bool) async throws {
        if let running = loginTask { return try await running.value }
        let task = Task { try await self.performLogin(automatic: automatic) }
        loginTask = task
        defer { loginTask = nil }
        try await task.value
    }

    private func performLogin(automatic: Bool) async throws {
        guard let credentials else { throw TccError.needsSignIn }
        if let until = loginGuard.lockedUntil, now() < until { throw TccError.locked(until: until) }
        if automatic, let lastLogin, now().timeIntervalSince(lastLogin) < Self.reloginInterval { throw TccError.sessionExpired }
        lastLogin = now()
        cookies = [:]
        do {
            _ = try await follow(try request("GET", "/portal"), body: nil)
            var post = try request("POST", "/portal")
            post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let form = [("timeOffset", String(-TimeZone.current.secondsFromGMT(for: now()) / 60)), ("UserName", credentials.username),
                        ("Password", credentials.password), ("RememberMe", "false")]
                .map { "\($0.0)=\(Self.formEncoded($0.1))" }.joined(separator: "&")
            let (page, posted) = try await follow(post, body: Data(form.utf8))
            if posted.statusCode == 401 { throw TccError.badCredentials }
            guard posted.statusCode == 200 else { throw TccError.unavailable(status: posted.statusCode) }
            let text = String(decoding: page, as: UTF8.self)
            if text.contains("The email or password provided is incorrect") || text.contains("The email address is not in the correct format") {
                throw TccError.badCredentials
            }
            if text.contains("will not operate without Cookies") { throw TccError.loginFailed }
            sawEmptyAuthCookie = false
            let (_, confirmed) = try await follow(try request("GET", "/portal"), body: nil)
            if sawEmptyAuthCookie { throw TccError.loginFailed }
            if confirmed.statusCode == 401 { throw TccError.badCredentials }
            guard confirmed.statusCode == 200 else { throw TccError.unavailable(status: confirmed.statusCode) }
            guard hasSession else { throw TccError.loginFailed }
            setGuard(TccLoginGuard())
        } catch LoginSignal.throttled {
            cookies = [:]
            throw TccError.locked(until: recordFailure(atLeast: 3) ?? now())
        } catch let failure as TccError {
            cookies = [:]
            if failure == .badCredentials || failure == .loginFailed { recordFailure(atLeast: 0) }
            throw failure
        }
    }

    @discardableResult
    private func recordFailure(atLeast floor: Int) -> Date? {
        var next = loginGuard
        next.failures = max(next.failures + 1, floor)
        next.lockedUntil = TccBackoff.lock(failures: next.failures).map { now().addingTimeInterval($0) }
        setGuard(next)
        return next.lockedUntil
    }

    private func setGuard(_ value: TccLoginGuard) {
        guard value != loginGuard else { return }
        loginGuard = value
        defaults?.set(try? JSONEncoder().encode(value), forKey: Self.guardKey)
    }

    private func follow(_ first: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse) {
        var request = first
        var body = body
        for _ in 0...Self.maxRedirects {
            let (data, response) = try await send(request, body: body)
            guard (300..<400).contains(response.statusCode) else { return (data, response) }
            guard let location = response.value(forHTTPHeaderField: "Location"),
                  let target = URL(string: location, relativeTo: request.url)?.absoluteURL else {
                throw TccError.unavailable(status: response.statusCode)
            }
            let next = try Self.checked(target)
            if next.absoluteString.contains("TooManyAttempts") { throw LoginSignal.throttled }
            if next.path.contains("/Error") { throw TccError.unavailable(status: response.statusCode) }
            request = self.request("GET", next)
            body = nil
        }
        throw TccError.unavailable(status: 310)
    }

    private func json(_ method: String, _ path: String, body: Data?) async throws -> Any {
        let (data, response) = try await send(try request(method, path), body: body)
        switch response.statusCode {
        case 200:
            guard response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true,
                  let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                throw TccError.unexpectedResponse
            }
            if loginGuard.failures != 0 { setGuard(TccLoginGuard()) }
            return value
        case 401, 403:
            cookies[Self.authCookie] = nil
            throw TccError.sessionExpired
        default:
            throw TccError.unavailable(status: response.statusCode)
        }
    }

    private func send(_ request: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if !cookies.isEmpty {
            request.setValue(cookies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        }
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request, body: body)
        } catch let known as TccError {
            throw known
        } catch is CancellationError {
            throw TccError.cancelled
        } catch let failure as URLError where failure.code == .cancelled {
            throw TccError.cancelled
        } catch {
            throw TccError.network
        }
        guard data.count <= Self.maxBody else { throw TccError.tooLarge }
        absorb(response)
        return (data, response)
    }

    private func absorb(_ response: HTTPURLResponse) {
        guard let header = response.value(forHTTPHeaderField: "Set-Cookie") else { return }
        for (name, value, expires) in Self.cookieUpdates(header) {
            if value.isEmpty, expires || name == Self.authCookie {
                cookies[name] = nil
                if name == Self.authCookie { sawEmptyAuthCookie = true }
            } else {
                cookies[name] = value
            }
        }
    }

    private func request(_ method: String, _ path: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: Self.origin)?.absoluteURL else { throw TccError.foreignHost }
        return request(method, try Self.checked(url))
    }

    private nonisolated func request(_ method: String, _ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = false
        return request
    }

    static func checked(_ url: URL) throws -> URL {
        guard url.scheme == "https", url.host == origin.host, url.port == nil, url.user == nil, url.password == nil else {
            throw TccError.foreignHost
        }
        return url
    }

    static func formEncoded(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    static func cookiePairs(_ header: String) -> [(String, String)] {
        cookieUpdates(header).map { ($0.0, $0.1) }
    }

    static func cookieUpdates(_ header: String) -> [(String, String, Bool)] {
        var cookies: [String] = []
        for piece in header.components(separatedBy: ",") {
            let lead = piece.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces)
            let name = lead.components(separatedBy: "=")[0]
            let startsCookie = lead.contains("=") && !name.isEmpty && !name.contains(" ")
            if startsCookie || cookies.isEmpty {
                cookies.append(piece)
            } else {
                cookies[cookies.count - 1] += "," + piece
            }
        }
        return cookies.compactMap { cookie in
            let pair = cookie.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces)
            guard let split = pair.firstIndex(of: "=") else { return nil }
            let name = String(pair[..<split])
            let attributes = cookie.lowercased()
            let expires = attributes.contains("expires=") || attributes.contains("max-age=")
            return name.isEmpty ? nil : (name, String(pair[pair.index(after: split)...]), expires)
        }
    }
}

public final class TccURLSessionTransport: NSObject, TccTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private var session: URLSession!

    public override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    public func send(_ request: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw TccError.foreignHost }
        _ = try TccClient.checked(url)
        var request = request
        request.httpBody = body
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw TccError.unexpectedResponse }
        guard http.expectedContentLength <= Int64(TccClient.maxBody) else { throw TccError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > TccClient.maxBody { throw TccError.tooLarge }
        }
        return (data, http)
    }
}
