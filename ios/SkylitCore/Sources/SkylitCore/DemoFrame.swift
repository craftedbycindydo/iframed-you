#if DEBUG
import Foundation
import CryptoKit
import CoreGraphics
import ImageIO

public final class StaticFrameBrowser: FrameBrowsing, @unchecked Sendable {
    private let lock = NSLock()
    private var addresses: [String: URL]
    private var continuation: AsyncStream<BrowseEvent>.Continuation?
    private let initial: [BrowseEvent]

    public init(events: [BrowseEvent] = [], addresses: [String: URL] = [:]) {
        initial = events
        self.addresses = addresses
    }

    public func events() -> AsyncStream<BrowseEvent> {
        AsyncStream { continuation in
            lock.withLock { self.continuation = continuation }
            initial.forEach { continuation.yield($0) }
        }
    }

    public func send(_ event: BrowseEvent) {
        lock.withLock { continuation }?.yield(event)
    }

    public func finish() {
        lock.withLock { continuation }?.finish()
    }

    public func move(_ service: String, to url: URL?) {
        lock.withLock { addresses[service] = url }
    }

    public func resolve(service: String) async throws -> URL {
        guard let url = lock.withLock({ addresses[service] }) else { throw FrameError.offline }
        return url
    }
}

public final class DemoFrameServer: HTTPTransport, @unchecked Sendable {
    public static let address = URL(string: "https://demo-frame.local:8765")!

    public struct Recorded: Sendable {
        public let url: URL
        public let method: String
        public let path: String
        public let query: String?
        public let headers: [String: String]
        public let body: Data?
    }

    public enum Bystander: Sendable {
        case waits
        case tapsPick
        case tapsDecoy
        case tapsCancel
        case letsItExpire
    }

    private enum Outcome {
        case waiting
        case approved
        case denied
        case expired
    }

    private struct Attempt {
        let session: String
        let commit: String
        let tokenHash: String
        let deviceName: String
        let nF: Data
        var code: String?
        var pick: String?
        var outcome = Outcome.waiting
        var deviceId = ""
    }

    private struct Device {
        let id: String
        let name: String
        let pairedAt: String
        let tokenHash: String
    }

    private struct Photo {
        let id: String
        let addedAt: String
        let data: Data
    }

    private let lock = NSLock()
    public let certificate: Data
    public let fingerprint: String
    public let frameId: String
    private let name: String
    private var rev = 1
    private var nextId = 1
    private var people: [[String: Any]] = []
    private var chores: [[String: Any]] = []
    private var shopping: [[String: Any]] = []
    private var calendars: [[String: Any]] = []
    private var location: Any = NSNull()
    private var appearance: [String: Any] = ["palette": "linen", "mode": "auto"]
    private var photos: [Photo] = []
    private var devices: [Device] = []
    private var windowOpen = false
    private var windowUsed = false
    private var attempt: Attempt?
    private var bystander = Bystander.tapsPick
    private var claimedFrameId: String?
    private var recorded: [Recorded] = []
    private var unreachable = false
    private var icloud: [String: Any]?
    private var supportsICloud = true

    public init(identity: String = "demo-frame", name: String = "Kitchen frame") {
        certificate = Data(identity.utf8)
        fingerprint = Pin.fingerprint(ofCertificate: certificate)
        frameId = Pin.frameId(for: fingerprint)
        self.name = name
    }

    public var credential: FrameCredential { FrameCredential(token: Self.demoToken, fp: fingerprint) }
    public var shownCode: String? { lock.withLock { attempt?.code } }
    public var shownPick: String? { lock.withLock { attempt?.pick } }

    public func openPairingWindow() {
        lock.withLock {
            windowOpen = true
            windowUsed = false
        }
    }

    public func setBystander(_ value: Bystander) {
        lock.withLock { bystander = value }
    }

    public func claimFrameId(_ value: String?) {
        lock.withLock { claimedFrameId = value }
    }

    public var requests: [Recorded] { lock.withLock { recorded } }
    public var revision: Int { lock.withLock { rev } }

    public func setUnreachable(_ value: Bool) {
        lock.withLock { unreachable = value }
    }

    public func authorize(token: String, deviceName: String) {
        lock.withLock {
            devices.append(Device(id: "d\(devices.count + 1)", name: deviceName, pairedAt: Self.timestamp(), tokenHash: Self.hash(token) ?? ""))
        }
    }

    fileprivate func checkReachable() throws {
        if lock.withLock({ unreachable }) { throw URLError(.cannotConnectToHost) }
    }

    public func revokeAll() {
        lock.withLock { devices.removeAll() }
    }

    public func removeICloudSupport() {
        lock.withLock { supportsICloud = false }
    }

    public func setICloudAlbum(name: String, count: Int, lastSync: String?, syncing: Bool, error: String?) {
        lock.withLock {
            icloud = ["name": name, "count": count, "lastSync": lastSync ?? NSNull(), "syncing": syncing, "error": error ?? NSNull()]
            rev += 1
        }
    }

    public func changeFromFrame(_ change: (inout [[String: Any]]) -> Void) {
        lock.withLock {
            change(&shopping)
            rev += 1
        }
    }

    public func send(_ request: URLRequest, body: Data?, onProgress: (@Sendable (Double) -> Void)?) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        onProgress?(0.5)
        let response: (Int, Any?, Data?) = try lock.withLock {
            if unreachable { throw URLError(.cannotConnectToHost) }
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            recorded.append(Recorded(url: request.url!, method: request.httpMethod ?? "GET", path: components.path, query: components.query,
                                     headers: request.allHTTPHeaderFields ?? [:], body: body))
            return route(request, components, body)
        }
        onProgress?(1)
        let data = try response.2 ?? response.1.map { try JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) } ?? Data()
        let http = HTTPURLResponse(url: request.url!, statusCode: response.0, httpVersion: "HTTP/1.1", headerFields: ["Connection": "close"])!
        return (data, http)
    }

    private func failure(_ status: Int, _ code: String, _ message: String) -> (Int, Any?, Data?) {
        (status, ["error": ["code": code, "message": message]], nil)
    }

    private func changed(_ extra: [String: Any] = [:]) -> (Int, Any?, Data?) {
        rev += 1
        return (200, extra.merging(["rev": rev]) { _, new in new }, nil)
    }

    private func route(_ request: URLRequest, _ components: URLComponents, _ body: Data?) -> (Int, Any?, Data?) {
        let method = request.httpMethod ?? "GET"
        let parts = components.path.split(separator: "/").map(String.init)
        guard let version = parts.first, version == "v1" || version == "v2" else { return failure(404, "not_found", "No such route") }
        let route = Array(parts.dropFirst())
        let isPhotoUpload = method == "POST" && route == ["photos"]
        if (body?.count ?? 0) > (isPhotoUpload ? 15 * 1024 * 1024 : 64 * 1024) {
            return failure(413, "too_large", "Body too large")
        }
        var json: [String: Any] = [:]
        if let body, !isPhotoUpload, !body.isEmpty {
            guard let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return failure(400, "bad_request", "Body must be a JSON object")
            }
            json = parsed
        }

        if version == "v2" {
            switch (method, route.first, route.count) {
            case ("GET", "info", 1):
                return (200, ["v": 2, "frameId": claimedFrameId ?? frameId, "name": name, "pairing": windowOpen && !windowUsed], nil)
            case ("POST", "pair", 2) where route[1] == "start":
                return startPairing(json)
            case ("POST", "pair", 2) where route[1] == "reveal":
                return revealPairing(json)
            case ("POST", "pair", 2) where route[1] == "cancel":
                guard attempt?.session == json["session"] as? String else { return failure(404, "not_found", "No such session") }
                attempt?.outcome = .denied
                return (204, nil, nil)
            case ("GET", "pair", 2) where route[1] == "result":
                return pairingResult(components.queryItems?.first { $0.name == "session" }?.value)
            default:
                return failure(404, "not_found", "No such route")
            }
        }

        let caller = request.value(forHTTPHeaderField: "Authorization")
            .flatMap { $0.hasPrefix("Bearer ") ? Self.hash(String($0.dropFirst(7))) : nil }
        guard let caller, devices.contains(where: { $0.tokenHash == caller }) else {
            return failure(401, "unauthorized", "Pair this phone first")
        }

        switch (method, route.first ?? "", route.count) {
        case ("GET", "devices", 1):
            return (200, devices.map { ["id": $0.id, "name": $0.name, "pairedAt": $0.pairedAt, "lastSeen": $0.pairedAt, "self": $0.tokenHash == caller] }, nil)
        case ("DELETE", "devices", 2):
            guard let device = devices.first(where: { $0.id == route[1] }) else { return failure(404, "not_found", "No such device") }
            guard device.tokenHash == caller else { return failure(403, "forbidden", "Remove other phones on the frame") }
            devices.removeAll { $0.id == route[1] }
            return (204, nil, nil)
        case ("GET", "state", 1):
            if let since = components.queryItems?.first(where: { $0.name == "since" })?.value, Int(since) == rev {
                return (304, nil, Data())
            }
            return (200, snapshot(), nil)
        case (_, "people", _):
            return collection(&people, key: "person", limit: 12, method, route, json, required: ["name", "color"], allowed: ["name", "color"]) { removed in
                for index in self.chores.indices where self.chores[index]["personId"] as? String == removed {
                    self.chores[index]["personId"] = NSNull()
                }
            }
        case ("PUT", "chores", 3) where route[2] == "done":
            return markDone(route[1], json)
        case (_, "chores", _):
            return collection(&chores, key: "chore", limit: 100, method, route, json, required: ["title"], allowed: ["title", "emoji", "personId", "days"],
                              defaults: ["emoji": "", "personId": NSNull(), "days": [Int](), "done": [String]()])
        case ("POST", "shopping", 2) where route[1] == "clear-done":
            shopping.removeAll { $0["done"] as? Bool == true }
            return changed()
        case (_, "shopping", _):
            return collection(&shopping, key: "item", limit: 200, method, route, json, required: ["name"], allowed: ["name", "qty", "note", "done"],
                              defaults: ["qty": 1, "note": "", "done": false])
        case ("PUT", "settings", 2) where route[1] == "location":
            guard Self.validName(json["name"]), let latitude = json["latitude"] as? Double, let longitude = json["longitude"] as? Double,
                  abs(latitude) <= 90, abs(longitude) <= 180 else { return failure(400, "bad_request", "Location needs a name, latitude and longitude") }
            location = json
            return changed()
        case (_, "settings", _) where route.count >= 2 && route[1] == "icloud-album":
            return icloudRoute(method, route, json)
        case ("PUT", "settings", 2) where route[1] == "appearance":
            guard let palette = json["palette"] as? String, Palettes.all.contains(where: { $0.id == palette }),
                  let mode = json["mode"] as? String, Palettes.modes.contains(mode) else { return failure(400, "bad_request", "Unknown palette or mode") }
            appearance = ["palette": palette, "mode": mode]
            return changed()
        case ("POST", "calendars", 1):
            guard calendars.count < 6 else { return failure(400, "bad_request", "The frame can hold 6 calendars") }
            guard Self.validName(json["name"]), let color = json["color"] as? String, Limits.isHexColor(color),
                  let url = json["url"] as? String, url.hasPrefix("https://"), url.contains(".ics") else {
                return failure(400, "bad_request", "That is not a calendar link the frame can use")
            }
            let calendar: [String: Any] = ["id": makeId("k"), "name": json["name"]!, "color": color]
            calendars.append(calendar)
            return changed(["calendar": calendar])
        case ("DELETE", "calendars", 2):
            guard calendars.contains(where: { $0["id"] as? String == route[1] }) else { return failure(404, "not_found", "No such calendar") }
            calendars.removeAll { $0["id"] as? String == route[1] }
            return changed()
        case ("GET", "photos", 1):
            return (200, photos.map { ["id": $0.id, "addedAt": $0.addedAt] }, nil)
        case ("POST", "photos", 1):
            guard let body, body.starts(with: [0xFF, 0xD8]), request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg" else {
                return failure(400, "bad_request", "Body must be one JPEG")
            }
            let id = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
            if let existing = photos.first(where: { $0.id == id }) {
                return (200, ["rev": rev, "photo": ["id": existing.id, "addedAt": existing.addedAt]], nil)
            }
            let photo = Photo(id: id, addedAt: Self.timestamp(), data: body)
            photos.insert(photo, at: 0)
            return changed(["photo": ["id": photo.id, "addedAt": photo.addedAt]])
        case ("GET", "photos", 2):
            guard let photo = photos.first(where: { $0.id == route[1] }) else { return failure(404, "not_found", "No such photo") }
            return (200, nil, photo.data)
        case ("DELETE", "photos", 2):
            guard photos.contains(where: { $0.id == route[1] }) else { return failure(404, "not_found", "No such photo") }
            photos.removeAll { $0.id == route[1] }
            rev += 1
            return (204, nil, nil)
        default:
            return failure(404, "not_found", "No such route")
        }
    }

    private func icloudRoute(_ method: String, _ route: [String], _ json: [String: Any]) -> (Int, Any?, Data?) {
        guard supportsICloud else { return failure(404, "not_found", "No such route") }
        switch (method, route.count) {
        case ("PUT", 2):
            guard let url = json["url"] as? String,
                  url.hasPrefix("https://www.icloud.com/sharedalbum/#") || url.hasPrefix("https://share.icloud.com/photos/") else {
                return failure(400, "bad_request", "That is not a public iCloud shared album link")
            }
            icloud = ["name": "Family album", "count": 0, "lastSync": NSNull(), "syncing": true, "error": NSNull()]
            return changed()
        case ("DELETE", 2):
            icloud = nil
            return changed()
        case ("POST", 3) where route[2] == "sync":
            guard icloud != nil else { return failure(409, "conflict", "No iCloud album is connected") }
            icloud?["syncing"] = true
            rev += 1
            return (204, nil, nil)
        default:
            return failure(404, "not_found", "No such route")
        }
    }

    private func startPairing(_ json: [String: Any]) -> (Int, Any?, Data?) {
        guard windowOpen else { return failure(409, "conflict", "Pairing is not open") }
        guard !windowUsed else { return failure(409, "pairing_busy", "Pairing is busy") }
        windowUsed = true
        guard let commit = json["commit"] as? String, Hex.isValid(commit, bytes: 32),
              let tokenHash = json["tokenHash"] as? String, Hex.isValid(tokenHash, bytes: 32),
              let deviceName = (json["deviceName"] as? String).flatMap(Limits.cleanDeviceName) else {
            return failure(400, "bad_request", "Needs commit, tokenHash and deviceName")
        }
        let nF = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let session = Hex.encode((0..<16).map { _ in UInt8.random(in: 0...255) })
        attempt = Attempt(session: session, commit: commit, tokenHash: tokenHash, deviceName: deviceName, nF: nF)
        return (200, ["session": session, "nF": Hex.encode(nF)], nil)
    }

    private func revealPairing(_ json: [String: Any]) -> (Int, Any?, Data?) {
        guard let current = attempt, current.session == json["session"] as? String, current.code == nil else {
            return failure(404, "not_found", "No such session")
        }
        guard let nP = (json["nP"] as? String).flatMap({ Hex.decode($0, bytes: 32) }), PairingCrypto.sha256(nP) == current.commit,
              let fpRaw = Hex.decode(fingerprint, bytes: Pin.bytes) else {
            attempt = nil
            return failure(400, "bad_request", "The reveal does not match the commit")
        }
        let derived = PairingCrypto.derive(nP: nP, nF: current.nF, fpRaw: fpRaw)
        attempt?.code = derived.code
        attempt?.pick = derived.pick
        return (204, nil, nil)
    }

    private func pairingResult(_ session: String?) -> (Int, Any?, Data?) {
        guard var current = attempt, current.session == session else { return failure(404, "not_found", "No such session") }
        if current.outcome == .waiting, current.code != nil {
            switch bystander {
            case .waits:
                break
            case .tapsPick:
                current.outcome = .approved
                current.deviceId = makeId("d")
                devices.append(Device(id: current.deviceId, name: current.deviceName, pairedAt: Self.timestamp(), tokenHash: current.tokenHash))
            case .tapsDecoy, .tapsCancel:
                current.outcome = .denied
            case .letsItExpire:
                current.outcome = .expired
            }
            attempt = current
        }
        switch current.outcome {
        case .waiting: return (202, nil, Data())
        case .approved: return (200, ["deviceId": current.deviceId, "frameId": claimedFrameId ?? frameId, "name": name], nil)
        case .denied: return failure(403, "forbidden", "Pairing was cancelled")
        case .expired: return failure(410, "gone", "Pairing expired")
        }
    }

    private func markDone(_ id: String, _ json: [String: Any]) -> (Int, Any?, Data?) {
        guard let index = chores.firstIndex(where: { $0["id"] as? String == id }) else { return failure(404, "not_found", "No such chore") }
        guard let date = json["date"] as? String, date.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil,
              let done = json["done"] as? Bool else { return failure(400, "bad_request", "Needs date and done") }
        var dates = (chores[index]["done"] as? [String] ?? []).filter { $0 != date }
        if done { dates.append(date) }
        chores[index]["done"] = dates
        return changed(["chore": chores[index]])
    }

    private func collection(_ list: inout [[String: Any]], key: String, limit: Int, _ method: String, _ route: [String], _ json: [String: Any],
                            required: [String], allowed: [String], defaults: [String: Any] = [:],
                            onRemove: (String) -> Void = { _ in }) -> (Int, Any?, Data?) {
        let fields = json.filter { allowed.contains($0.key) }
        guard valid(fields) else { return failure(400, "bad_request", "A field is missing or out of range") }
        switch (method, route.count) {
        case ("POST", 1):
            guard list.count < limit else { return failure(400, "bad_request", "The frame is full") }
            guard required.allSatisfy({ fields[$0] != nil }) else { return failure(400, "bad_request", "A field is missing or out of range") }
            var object = defaults.merging(fields) { _, new in new }
            object["id"] = makeId(String(key.prefix(1)))
            list.append(object)
            return changed([key: object])
        case ("PATCH", 2):
            guard let index = list.firstIndex(where: { $0["id"] as? String == route[1] }) else { return failure(404, "not_found", "No such \(key)") }
            list[index].merge(fields) { _, new in new }
            return changed([key: list[index]])
        case ("DELETE", 2):
            guard list.contains(where: { $0["id"] as? String == route[1] }) else { return failure(404, "not_found", "No such \(key)") }
            list.removeAll { $0["id"] as? String == route[1] }
            onRemove(route[1])
            return changed()
        default:
            return failure(404, "not_found", "No such route")
        }
    }

    private func valid(_ fields: [String: Any]) -> Bool {
        for (key, value) in fields {
            switch key {
            case "name", "title":
                if !Self.validName(value) { return false }
            case "color":
                guard let color = value as? String, Limits.isHexColor(color) else { return false }
            case "qty":
                guard let qty = value as? Int, Limits.quantity.contains(qty) else { return false }
            case "days":
                guard let days = value as? [Int], days.allSatisfy({ (0...6).contains($0) }) else { return false }
            case "personId":
                if value is NSNull { continue }
                guard let id = value as? String, people.contains(where: { $0["id"] as? String == id }) else { return false }
            default:
                continue
            }
        }
        return true
    }

    private func snapshot() -> [String: Any] {
        ["rev": rev, "people": people, "chores": chores, "shopping": shopping,
         "settings": supportsICloud ? ["location": location, "appearance": appearance, "icloudAlbum": icloud.map { $0 as Any } ?? NSNull()]
            : ["location": location, "appearance": appearance],
         "calendars": calendars, "photos": ["count": photos.count]]
    }

    private func makeId(_ prefix: String) -> String {
        defer { nextId += 1 }
        return "\(prefix)\(nextId)"
    }

    private static func validName(_ value: Any?) -> Bool {
        (value as? String).flatMap(Limits.cleanName) != nil
    }

    private static func hash(_ token: String) -> String? {
        Hex.decode(token, bytes: 32).map(PairingCrypto.sha256)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

public final class DemoNetwork: FrameConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var hosts: [String: DemoFrameServer]

    public init(_ hosts: [String: DemoFrameServer] = [:]) {
        self.hosts = hosts
    }

    public convenience init(_ server: DemoFrameServer) {
        self.init([DemoFrameServer.address.host ?? "": server])
    }

    public func place(_ server: DemoFrameServer?, at host: String) {
        lock.withLock { hosts[host] = server }
    }

    public func probe() -> FrameTransport {
        DemoLink(network: self, gate: TrustGate(.probe))
    }

    public func pairing() -> FrameTransport {
        DemoLink(network: self, gate: TrustGate(.pairing))
    }

    public func pinned(_ fp: String) -> HTTPTransport {
        DemoLink(network: self, gate: TrustGate(.pinned(fp)))
    }

    fileprivate func server(for request: URLRequest) throws -> DemoFrameServer {
        guard let url = request.url, url.scheme == "https", let server = lock.withLock({ hosts[url.host ?? ""] }) else {
            throw URLError(.cannotConnectToHost)
        }
        return server
    }
}

private struct DemoLink: FrameTransport {
    let network: DemoNetwork
    let gate: TrustGate

    var fingerprint: String? { gate.fingerprint }

    func send(_ request: URLRequest, body: Data?, onProgress: (@Sendable (Double) -> Void)?) async throws -> (Data, HTTPURLResponse) {
        let server = try network.server(for: request)
        try server.checkReachable()
        guard gate.accepts(leaf: server.certificate) else { throw FrameError.pinMismatch }
        return try await server.send(request, body: body, onProgress: onProgress)
    }
}

public extension DemoFrameServer {
    static let demoToken = String(repeating: "d", count: 64)
    static let otherToken = String(repeating: "e", count: 64)

    static func sample(now: Date = Date()) -> DemoFrameServer {
        let server = DemoFrameServer()
        let zone = TimeZone(identifier: "America/Edmonton") ?? .current
        let today = ChoreLogic.dateString(now, timeZone: zone)
        server.authorize(token: demoToken, deviceName: "Karan's iPhone")
        server.authorize(token: otherToken, deviceName: "Hallway tablet")
        server.lock.withLock {
            server.people = [
                ["id": "p1", "name": "Maya", "color": "#00A36C"],
                ["id": "p2", "name": "Leo", "color": "#C98A3C"],
                ["id": "p3", "name": "Sam", "color": "#8B5779"],
            ]
            server.chores = [
                ["id": "c1", "title": "Make bed", "emoji": "🛏️", "personId": "p1", "days": [Int](), "done": [today]],
                ["id": "c2", "title": "Feed Momo", "emoji": "🐈", "personId": "p1", "days": [Int](), "done": [String]()],
                ["id": "c3", "title": "Pack school bag", "emoji": "🎒", "personId": "p2", "days": [1, 2, 3, 4, 5], "done": [String]()],
                ["id": "c4", "title": "Water the plants", "emoji": "🪴", "personId": "p2", "days": [Int](), "done": [today]],
                ["id": "c5", "title": "Set the table", "emoji": "🍽️", "personId": "p3", "days": [Int](), "done": [String]()],
                ["id": "c6", "title": "Take out recycling", "emoji": "♻️", "personId": NSNull(), "days": [Int](), "done": [String]()],
                ["id": "c7", "title": "Tidy the hallway", "emoji": "", "personId": NSNull(), "days": [0, 6], "done": [String]()],
            ]
            server.shopping = [
                ["id": "s1", "name": "Milk", "qty": 2, "note": "", "done": false],
                ["id": "s2", "name": "Sourdough", "qty": 1, "note": "From the corner bakery", "done": false],
                ["id": "s3", "name": "Oranges", "qty": 6, "note": "", "done": false],
                ["id": "s4", "name": "Oat cereal", "qty": 1, "note": "", "done": true],
                ["id": "s5", "name": "Dish soap", "qty": 1, "note": "", "done": true],
            ]
            server.calendars = [
                ["id": "k1", "name": "Family", "color": "#2D5BFF"],
                ["id": "k2", "name": "School", "color": "#C98A3C"],
            ]
            server.location = ["name": "Calgary", "latitude": 51.05, "longitude": -114.07, "timezone": "America/Edmonton"]
            server.photos = samplePhotos()
            server.nextId = 20
            server.rev = 42
        }
        return server
    }

    private static func samplePhotos() -> [Photo] {
        let scenes: [(sky: [CGFloat], hill: [CGFloat], sun: [CGFloat])] = [
            ([0.90, 0.83, 0.73], [0.54, 0.58, 0.47], [0.84, 0.59, 0.31]),
            ([0.84, 0.89, 0.91], [0.27, 0.46, 0.54], [0.96, 0.98, 0.98]),
            ([0.93, 0.89, 0.91], [0.55, 0.34, 0.47], [0.91, 0.83, 0.87]),
            ([0.89, 0.91, 0.87], [0.32, 0.40, 0.28], [0.84, 0.67, 0.38]),
            ([0.92, 0.82, 0.71], [0.60, 0.32, 0.23], [1.00, 0.98, 0.94]),
            ([0.84, 0.87, 0.81], [0.45, 0.53, 0.43], [0.90, 0.74, 0.47]),
        ]
        return scenes.enumerated().compactMap { index, scene in
            guard let data = sceneJPEG(scene.sky, scene.hill, scene.sun, variant: index) else { return nil }
            let id = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return Photo(id: id, addedAt: timestamp(), data: data)
        }
    }

    private static func sceneJPEG(_ sky: [CGFloat], _ hill: [CGFloat], _ sun: [CGFloat], variant: Int) -> Data? {
        let width = 640, height = 480
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(red: sky[0], green: sky[1], blue: sky[2], alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: sun[0], green: sun[1], blue: sun[2], alpha: 1)
        context.fillEllipse(in: CGRect(x: 380 - variant * 50, y: 280, width: 110, height: 110))
        context.setFillColor(red: hill[0], green: hill[1], blue: hill[2], alpha: 0.75)
        context.fillEllipse(in: CGRect(x: -160 + variant * 30, y: -230, width: 620, height: 420))
        context.setFillColor(red: hill[0] * 0.75, green: hill[1] * 0.75, blue: hill[2] * 0.75, alpha: 1)
        context.fillEllipse(in: CGRect(x: 200 - variant * 20, y: -260, width: 640, height: 400))
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
#endif
