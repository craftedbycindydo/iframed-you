import Foundation

public struct FrameAPI: Sendable {
    public var baseURL: URL
    public var token: String?
    private let transport: HTTPTransport

    public init(baseURL: URL, token: String? = nil, transport: HTTPTransport) {
        self.baseURL = baseURL
        self.token = token
        self.transport = transport
    }

    public func info() async throws -> FrameInfo {
        try await decode(send("GET", "/v2/info", authorized: false))
    }

    public func pairStart(commit: String, tokenHash: String, deviceName: String) async throws -> PairSession {
        try await decode(send("POST", "/v2/pair/start", json: ["commit": commit, "tokenHash": tokenHash, "deviceName": deviceName], authorized: false))
    }

    public func pairReveal(session: String, nP: String) async throws {
        _ = try await send("POST", "/v2/pair/reveal", json: ["session": session, "nP": nP], authorized: false)
    }

    public func pairCancel(session: String) async throws {
        _ = try await send("POST", "/v2/pair/cancel", json: ["session": session], authorized: false)
    }

    public func pairResult(session: String) async throws -> PairResult? {
        let (data, status) = try await exchange("GET", "/v2/pair/result", query: [URLQueryItem(name: "session", value: session)], authorized: false)
        guard status != 202 else { return nil }
        guard status == 200 else { throw FrameError.invalidResponse }
        return try decode(data)
    }

    public func devices() async throws -> [PairedDevice] {
        try await decode(send("GET", "/v1/devices"))
    }

    public func removeDevice(id: String) async throws {
        _ = try await send("DELETE", "/v1/devices/\(escaped(id))")
    }

    public func state(since rev: Int? = nil) async throws -> FrameState? {
        let query = rev.map { [URLQueryItem(name: "since", value: String($0))] }
        let (data, status) = try await exchange("GET", "/v1/state", query: query)
        return status == 304 ? nil : try decode(data)
    }

    public func addPerson(name: String, color: String) async throws -> MutationResult {
        try await mutate("POST", "/v1/people", ["name": name, "color": color])
    }

    public func updatePerson(id: String, name: String? = nil, color: String? = nil) async throws -> MutationResult {
        try await mutate("PATCH", "/v1/people/\(escaped(id))", present(["name": name, "color": color]))
    }

    public func deletePerson(id: String) async throws -> MutationResult {
        try await mutate("DELETE", "/v1/people/\(escaped(id))")
    }

    public func addChore(_ draft: ChoreDraft) async throws -> MutationResult {
        var body: [String: Any] = ["title": draft.title, "days": draft.days]
        if !draft.emoji.isEmpty { body["emoji"] = draft.emoji }
        if let personId = draft.personId { body["personId"] = personId }
        return try await mutate("POST", "/v1/chores", body)
    }

    public func updateChore(id: String, _ draft: ChoreDraft) async throws -> MutationResult {
        try await mutate("PATCH", "/v1/chores/\(escaped(id))", [
            "title": draft.title,
            "emoji": draft.emoji,
            "personId": draft.personId ?? NSNull(),
            "days": draft.days,
        ])
    }

    public func deleteChore(id: String) async throws -> MutationResult {
        try await mutate("DELETE", "/v1/chores/\(escaped(id))")
    }

    public func setChoreDone(id: String, date: String, done: Bool) async throws -> MutationResult {
        try await mutate("PUT", "/v1/chores/\(escaped(id))/done", ["date": date, "done": done])
    }

    public func addItem(_ draft: ShoppingDraft) async throws -> MutationResult {
        var body: [String: Any] = ["name": draft.name, "qty": draft.qty]
        if !draft.note.isEmpty { body["note"] = draft.note }
        return try await mutate("POST", "/v1/shopping", body)
    }

    public func updateItem(id: String, name: String? = nil, qty: Int? = nil, note: String? = nil, done: Bool? = nil) async throws -> MutationResult {
        try await mutate("PATCH", "/v1/shopping/\(escaped(id))", present(["name": name, "qty": qty, "note": note, "done": done]))
    }

    public func deleteItem(id: String) async throws -> MutationResult {
        try await mutate("DELETE", "/v1/shopping/\(escaped(id))")
    }

    public func clearDoneItems() async throws -> MutationResult {
        try await mutate("POST", "/v1/shopping/clear-done")
    }

    public func setLocation(_ location: FrameLocation) async throws -> MutationResult {
        try await mutate("PUT", "/v1/settings/location", present([
            "name": location.name, "latitude": location.latitude, "longitude": location.longitude, "timezone": location.timezone,
        ]))
    }

    public func setAppearance(_ appearance: FrameAppearance) async throws -> MutationResult {
        try await mutate("PUT", "/v1/settings/appearance", ["palette": appearance.palette, "mode": appearance.mode])
    }

    public func connectICloudAlbum(url: String) async throws -> MutationResult {
        try await mutate("PUT", "/v1/settings/icloud-album", ["url": url])
    }

    public func disconnectICloudAlbum() async throws -> MutationResult {
        try await mutate("DELETE", "/v1/settings/icloud-album")
    }

    public func syncICloudAlbum() async throws {
        _ = try await send("POST", "/v1/settings/icloud-album/sync")
    }

    public func thermostatAccount() async throws -> TccCredentials? {
        do {
            let found = try JSONSerialization.jsonObject(with: try await send("GET", "/v1/settings/thermostat-account")) as? [String: Any]
            guard let email = found?["email"] as? String, let password = found?["password"] as? String else { throw FrameError.invalidResponse }
            return TccCredentials(username: email, password: password)
        } catch FrameError.api(404, _) {
            return nil
        }
    }

    public func setThermostatAccount(_ account: TccCredentials) async throws {
        _ = try await send("PUT", "/v1/settings/thermostat-account", json: ["email": account.username, "password": account.password])
    }

    public func addCalendar(name: String, color: String, url: String) async throws -> MutationResult {
        try await mutate("POST", "/v1/calendars", ["name": name, "color": color, "url": url])
    }

    public func deleteCalendar(id: String) async throws -> MutationResult {
        try await mutate("DELETE", "/v1/calendars/\(escaped(id))")
    }

    public func photos() async throws -> [PhotoRef] {
        try await decode(send("GET", "/v1/photos"))
    }

    public func uploadPhoto(_ jpeg: Data, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> MutationResult {
        guard jpeg.count <= Limits.photoBytes else {
            throw FrameError.api(status: 413, code: "too_large")
        }
        var request = try request("POST", "/v1/photos", query: nil, authorized: true)
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        do {
            return try result(from: try await checked(deliver(request, body: jpeg, onProgress: onProgress)).0)
        } catch FrameError.connectionLost {
            throw FrameError.uploadRejected
        }
    }

    public func photoData(id: String) async throws -> Data {
        try await send("GET", "/v1/photos/\(escaped(id))")
    }

    public func deletePhoto(id: String) async throws -> MutationResult {
        try await mutate("DELETE", "/v1/photos/\(escaped(id))")
    }

    private func mutate(_ method: String, _ path: String, _ json: [String: Any]? = nil) async throws -> MutationResult {
        try result(from: try await send(method, path, json: json))
    }

    private func result(from data: Data) throws -> MutationResult {
        data.isEmpty ? MutationResult() : try decode(data)
    }

    private func send(_ method: String, _ path: String, json: [String: Any]? = nil, authorized: Bool = true) async throws -> Data {
        try await exchange(method, path, json: json, authorized: authorized).0
    }

    private func exchange(_ method: String, _ path: String, query: [URLQueryItem]? = nil,
                          json: [String: Any]? = nil, authorized: Bool = true) async throws -> (Data, Int) {
        var request = try request(method, path, query: query, authorized: authorized)
        var body: Data?
        if let json {
            body = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        return try checked(try await deliver(request, body: body, onProgress: nil))
    }

    private func request(_ method: String, _ path: String, query: [URLQueryItem]?, authorized: Bool) throws -> URLRequest {
        guard baseURL.scheme == "https", var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw FrameError.offline }
        components.percentEncodedPath = path
        components.queryItems = query
        guard let url = components.url else { throw FrameError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized {
            guard let token else { throw FrameError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func deliver(_ request: URLRequest, body: Data?, onProgress: (@Sendable (Double) -> Void)?) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request, body: body, onProgress: onProgress)
        } catch {
            throw FrameError.from(error)
        }
    }

    private func checked(_ response: (Data, HTTPURLResponse)) throws -> (Data, Int) {
        let status = response.1.statusCode
        guard (200..<300).contains(status) || status == 304 else {
            throw FrameError.from(status: status, body: response.0)
        }
        return (response.0, status)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FrameError.invalidResponse
        }
    }

    private func escaped(_ id: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        return id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
    }

    private func present(_ fields: [String: Any?]) -> [String: Any] {
        fields.compactMapValues { $0 }
    }
}
