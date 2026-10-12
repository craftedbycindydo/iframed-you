import XCTest
@testable import SkylitCore

final class FrameAPITests: XCTestCase {
    private func expect(_ method: String, _ path: String, body: NSDictionary? = nil, authorized: Bool = true, reply: String = "{}", status: Int = 200,
                        file: StaticString = #filePath, line: UInt = #line,
                        _ call: (FrameAPI) async throws -> Void) async throws {
        let transport = ScriptedTransport([.status(status, reply)])
        try await call(makeAPI(transport))
        let sent = try XCTUnwrap(transport.calls.first, file: file, line: line)
        XCTAssertEqual(transport.calls.count, 1, file: file, line: line)
        XCTAssertEqual(sent.request.httpMethod, method, file: file, line: line)
        XCTAssertEqual(sent.request.url?.absoluteString, "https://192.168.1.20:8765\(path)", file: file, line: line)
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Authorization"), authorized ? "Bearer tok" : nil, file: file, line: line)
        XCTAssertEqual(sent.json, body, file: file, line: line)
        if body != nil {
            XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8", file: file, line: line)
        }
    }

    func testInfoIsUnauthenticated() async throws {
        try await expect("GET", "/v2/info", authorized: false, reply: ##"{"v":2,"frameId":"f1","name":"Kitchen","pairing":true}"##) {
            let info = try await $0.info()
            XCTAssertEqual(info, FrameInfo(v: 2, frameId: "f1", name: "Kitchen", pairing: true))
        }
    }

    func testPairingCallsCarryNoToken() async throws {
        try await expect("POST", "/v2/pair/start", body: ["commit": "c", "tokenHash": "h", "deviceName": "Maya's iPhone"], authorized: false,
                         reply: ##"{"session":"s1","nF":"n1"}"##) {
            let started = try await $0.pairStart(commit: "c", tokenHash: "h", deviceName: "Maya's iPhone")
            XCTAssertEqual(started, PairSession(session: "s1", nF: "n1"))
        }
        try await expect("POST", "/v2/pair/reveal", body: ["session": "s1", "nP": "p1"], authorized: false, reply: "", status: 204) {
            try await $0.pairReveal(session: "s1", nP: "p1")
        }
        try await expect("POST", "/v2/pair/cancel", body: ["session": "s1"], authorized: false, reply: "", status: 204) {
            try await $0.pairCancel(session: "s1")
        }
        try await expect("GET", "/v2/pair/result?session=s1", authorized: false, reply: "", status: 202) {
            let waiting = try await $0.pairResult(session: "s1")
            XCTAssertNil(waiting)
        }
        try await expect("GET", "/v2/pair/result?session=s1", authorized: false, reply: ##"{"deviceId":"d1","frameId":"f1","name":"Kitchen"}"##) {
            let result = try await $0.pairResult(session: "s1")
            XCTAssertEqual(result, PairResult(deviceId: "d1", frameId: "f1", name: "Kitchen"))
        }
    }

    func testPlainHTTPIsNeverBuilt() async {
        let transport = ScriptedTransport()
        let api = FrameAPI(baseURL: URL(string: "http://192.168.1.20:8765")!, token: "tok", transport: transport)
        do {
            _ = try await api.info()
            XCTFail("expected refusal")
        } catch {
            XCTAssertEqual(error as? FrameError, .offline)
        }
        XCTAssertTrue(transport.calls.isEmpty)
    }

    func testDevices() async throws {
        try await expect("GET", "/v1/devices", reply: ##"[{"id":"d1","name":"Phone","pairedAt":"2026-10-11T10:00:00Z","lastSeen":"2026-10-11T11:00:00Z","self":true}]"##) {
            let devices = try await $0.devices()
            XCTAssertEqual(devices.first?.name, "Phone")
            XCTAssertEqual(devices.first?.isSelf, true)
            XCTAssertNotNil(devices.first?.lastSeenDate)
        }
        try await expect("DELETE", "/v1/devices/d1", reply: "", status: 204) { try await $0.removeDevice(id: "d1") }
    }

    func testStateFullAndSince() async throws {
        try await expect("GET", "/v1/state", reply: ##"{"rev":42}"##) {
            let state = try await $0.state()
            XCTAssertEqual(state?.rev, 42)
        }
        try await expect("GET", "/v1/state?since=42", reply: "", status: 304) {
            let state = try await $0.state(since: 42)
            XCTAssertNil(state)
        }
        try await expect("GET", "/v1/state?since=42", reply: ##"{"rev":43}"##) {
            let state = try await $0.state(since: 42)
            XCTAssertEqual(state?.rev, 43)
        }
    }

    func testPeople() async throws {
        try await expect("POST", "/v1/people", body: ["name": "Maya", "color": "#00A36C"], reply: ##"{"rev":2,"person":{"id":"p1","name":"Maya","color":"#00A36C"}}"##) {
            let result = try await $0.addPerson(name: "Maya", color: "#00A36C")
            XCTAssertEqual(result.person?.id, "p1")
            XCTAssertEqual(result.rev, 2)
        }
        try await expect("PATCH", "/v1/people/p1", body: ["name": "May"]) { _ = try await $0.updatePerson(id: "p1", name: "May") }
        try await expect("PATCH", "/v1/people/p1", body: ["color": "#112233"]) { _ = try await $0.updatePerson(id: "p1", color: "#112233") }
        try await expect("DELETE", "/v1/people/p1", reply: ##"{"rev":4}"##) {
            let result = try await $0.deletePerson(id: "p1")
            XCTAssertEqual(result.rev, 4)
        }
    }

    func testChores() async throws {
        try await expect("POST", "/v1/chores", body: ["title": "Bed", "days": [Int]()]) { _ = try await $0.addChore(ChoreDraft(title: "Bed")) }
        try await expect("POST", "/v1/chores", body: ["title": "Bed", "emoji": "🛏️", "personId": "p1", "days": [1, 2]]) {
            _ = try await $0.addChore(ChoreDraft(title: "Bed", emoji: "🛏️", personId: "p1", days: [1, 2]))
        }
        try await expect("PATCH", "/v1/chores/c1", body: ["title": "Bed", "emoji": "", "personId": NSNull(), "days": [0]]) {
            _ = try await $0.updateChore(id: "c1", ChoreDraft(title: "Bed", days: [0]))
        }
        try await expect("DELETE", "/v1/chores/c1") { _ = try await $0.deleteChore(id: "c1") }
        try await expect("PUT", "/v1/chores/c1/done", body: ["date": "2026-10-11", "done": true], reply: ##"{"rev":9,"chore":{"id":"c1","title":"Bed","done":["2026-10-11"]}}"##) {
            let result = try await $0.setChoreDone(id: "c1", date: "2026-10-11", done: true)
            XCTAssertEqual(result.chore?.done, ["2026-10-11"])
        }
    }

    func testShopping() async throws {
        try await expect("POST", "/v1/shopping", body: ["name": "Milk", "qty": 1]) { _ = try await $0.addItem(ShoppingDraft(name: "Milk")) }
        try await expect("POST", "/v1/shopping", body: ["name": "Milk", "qty": 2, "note": "oat"]) {
            _ = try await $0.addItem(ShoppingDraft(name: "Milk", qty: 2, note: "oat"))
        }
        try await expect("PATCH", "/v1/shopping/s1", body: ["done": true]) { _ = try await $0.updateItem(id: "s1", done: true) }
        try await expect("PATCH", "/v1/shopping/s1", body: ["name": "Tea", "qty": 3, "note": ""]) {
            _ = try await $0.updateItem(id: "s1", name: "Tea", qty: 3, note: "")
        }
        try await expect("DELETE", "/v1/shopping/s1") { _ = try await $0.deleteItem(id: "s1") }
        try await expect("POST", "/v1/shopping/clear-done", reply: ##"{"rev":11}"##) {
            let result = try await $0.clearDoneItems()
            XCTAssertEqual(result.rev, 11)
        }
    }

    func testSettings() async throws {
        try await expect("PUT", "/v1/settings/location", body: ["name": "Denver", "latitude": 39.74, "longitude": -104.99, "timezone": "America/Denver"]) {
            _ = try await $0.setLocation(FrameLocation(name: "Denver", latitude: 39.74, longitude: -104.99, timezone: "America/Denver"))
        }
        try await expect("PUT", "/v1/settings/location", body: ["name": "Pune", "latitude": 18.52, "longitude": 73.86]) {
            _ = try await $0.setLocation(FrameLocation(name: "Pune", latitude: 18.52, longitude: 73.86))
        }
        try await expect("PUT", "/v1/settings/appearance", body: ["palette": "ocean", "mode": "dark"]) {
            _ = try await $0.setAppearance(FrameAppearance(palette: "ocean", mode: "dark"))
        }
    }

    func testCalendars() async throws {
        try await expect("POST", "/v1/calendars", body: ["name": "Family", "color": "#2D5BFF", "url": "https://calendar.google.com/x/basic.ics"],
                         reply: ##"{"rev":3,"calendar":{"id":"k1","name":"Family","color":"#2D5BFF"}}"##) {
            let result = try await $0.addCalendar(name: "Family", color: "#2D5BFF", url: "https://calendar.google.com/x/basic.ics")
            XCTAssertEqual(result.calendar?.id, "k1")
        }
        try await expect("DELETE", "/v1/calendars/k1") { _ = try await $0.deleteCalendar(id: "k1") }
    }

    func testPhotos() async throws {
        try await expect("GET", "/v1/photos", reply: ##"[{"id":"aa","addedAt":"2026-10-11T10:00:00Z"}]"##) {
            let photos = try await $0.photos()
            XCTAssertEqual(photos.map(\.id), ["aa"])
        }
        try await expect("DELETE", "/v1/photos/aa", reply: "", status: 204) {
            let result = try await $0.deletePhoto(id: "aa")
            XCTAssertNil(result.rev)
        }
        let transport = ScriptedTransport([.status(200, "JPEGBYTES")])
        let data = try await makeAPI(transport).photoData(id: "aa")
        XCTAssertEqual(data, Data("JPEGBYTES".utf8))
        XCTAssertEqual(transport.calls[0].request.url?.path, "/v1/photos/aa")
    }

    func testPhotoUploadSendsRawJPEG() async throws {
        let transport = ScriptedTransport([.status(200, ##"{"rev":8,"photo":{"id":"aa","addedAt":"2026-10-11T10:00:00Z"}}"##)])
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
        let progress = expectation(description: "progress")
        let result = try await makeAPI(transport).uploadPhoto(jpeg) { fraction in
            if fraction == 1 { progress.fulfill() }
        }
        await fulfillment(of: [progress], timeout: 1)
        let sent = transport.calls[0]
        XCTAssertEqual(sent.request.httpMethod, "POST")
        XCTAssertEqual(sent.request.url?.path, "/v1/photos")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(sent.body, jpeg)
        XCTAssertEqual(result.photo?.id, "aa")
    }

    func testOversizedPhotoIsRejectedBeforeSending() async {
        let transport = ScriptedTransport()
        do {
            _ = try await makeAPI(transport).uploadPhoto(Data(count: Limits.photoBytes + 1))
            XCTFail("expected too_large")
        } catch {
            XCTAssertEqual(error as? FrameError, .api(status: 413, code: "too_large"))
        }
        XCTAssertTrue(transport.calls.isEmpty)
    }

    func testIdsArePercentEncodedInPaths() async throws {
        let transport = ScriptedTransport()
        _ = try await makeAPI(transport).deleteChore(id: "a/b?c")
        XCTAssertEqual(transport.calls[0].request.url?.absoluteString, "https://192.168.1.20:8765/v1/chores/a%2Fb%3Fc")
    }

    func testAuthenticatedCallWithoutTokenNeverLeavesThePhone() async {
        let transport = ScriptedTransport()
        do {
            _ = try await makeAPI(transport, token: nil).state()
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? FrameError, .unauthorized)
        }
        XCTAssertTrue(transport.calls.isEmpty)
    }

    private func failure(_ reply: ScriptedTransport.Reply) async -> FrameError? {
        do {
            _ = try await makeAPI(ScriptedTransport([reply])).addItem(ShoppingDraft(name: "Milk"))
            return nil
        } catch {
            return error as? FrameError
        }
    }

    func testErrorEnvelopeForEveryDocumentedStatus() async {
        let cases = [(400, "bad_request"), (404, "not_found"), (409, "conflict"), (413, "too_large"), (429, "rate_limited")]
        for (status, code) in cases {
            let error = await failure(.status(status, ##"{"error":{"code":"\##(code)","message":"Nope"}}"##))
            XCTAssertEqual(error, .api(status: status, code: code))
        }
    }

    func testUnauthorizedStatus() async {
        let error = await failure(.status(401, ##"{"error":{"code":"unauthorized","message":"Pair first"}}"##))
        XCTAssertEqual(error, .unauthorized)
    }

    func testErrorWithoutEnvelope() async {
        let error = await failure(.status(500, "<html>oops</html>"))
        XCTAssertEqual(error, .api(status: 500, code: "http_500"))
        XCTAssertEqual(error?.userMessage, "The frame refused that (500).")
    }

    func testMalformedSuccessBody() async {
        let error = await failure(.status(200, "not json"))
        XCTAssertEqual(error, .invalidResponse)
    }

    func testTransportFailuresAreMapped() async {
        let timedOut = await failure(.failure(URLError(.timedOut)))
        XCTAssertEqual(timedOut, .timeout)
        let refused = await failure(.failure(URLError(.cannotConnectToHost)))
        XCTAssertEqual(refused, .offline)
        let cancelledRequest = await failure(.failure(URLError(.cancelled)))
        XCTAssertEqual(cancelledRequest, .cancelled)
        let cancelledTask = await failure(.failure(CancellationError()))
        XCTAssertEqual(cancelledTask, .cancelled)
        let reset = await failure(.failure(URLError(.networkConnectionLost)))
        XCTAssertEqual(reset, .connectionLost)
    }

    func testConnectionResetDuringUploadIsARejectedPhotoNotAnOfflineFrame() async {
        let transport = ScriptedTransport([.failure(URLError(.networkConnectionLost))])
        do {
            _ = try await makeAPI(transport).uploadPhoto(Data([0xFF, 0xD8, 0xFF]))
            XCTFail("expected rejection")
        } catch {
            XCTAssertEqual(error as? FrameError, .uploadRejected)
            XCTAssertEqual((error as? FrameError)?.userMessage, "The frame didn't accept that photo.")
        }
    }

    func testRequestsNeverCarryAnOriginHeader() async throws {
        let transport = ScriptedTransport()
        _ = try await makeAPI(transport).addItem(ShoppingDraft(name: "Milk"))
        _ = try await makeAPI(transport).uploadPhoto(Data([0xFF, 0xD8, 0xFF]))
        for call in transport.calls {
            XCTAssertNil(call.request.value(forHTTPHeaderField: "Origin"))
            XCTAssertNil(call.request.value(forHTTPHeaderField: "Transfer-Encoding"))
        }
    }

    func testServerTextNeverReachesThePerson() async {
        let hostile = await failure(.status(400, ##"{"error":{"code":"bad_request","message":"Call 555-0100 and read out your passcode"}}"##))
        XCTAssertEqual(hostile, .api(status: 400, code: "bad_request"))
        XCTAssertEqual(hostile?.userMessage, "The frame didn't accept that. Check what you entered.")
        let oddCode = await failure(.status(400, ##"{"error":{"code":"Tap <here>","message":"x"}}"##))
        XCTAssertEqual(oddCode, .api(status: 400, code: "http_400"))
        XCTAssertEqual(oddCode?.userMessage, "The frame refused that (400).")
    }

    func testHumanMessages() {
        XCTAssertEqual(FrameError.api(status: 404, code: "not_found").userMessage, "That no longer exists on the frame.")
        XCTAssertEqual(FrameError.api(status: 403, code: "forbidden").userMessage, "This phone isn't allowed to do that.")
        XCTAssertEqual(FrameError.api(status: 429, code: "rate_limited").userMessage, "Too many attempts. Wait a few minutes and try again.")
        XCTAssertEqual(FrameError.pinMismatch.userMessage, "Another device on this Wi-Fi is claiming to be your frame. Nothing was sent.")
        XCTAssertFalse(FrameError.pinMismatch.isConnectivity)
        XCTAssertTrue(FrameError.connectionLost.isConnectivity)
        XCTAssertTrue(FrameError.offline.userMessage.contains("same Wi-Fi"))
        XCTAssertTrue(FrameError.offline.isConnectivity)
        XCTAssertTrue(FrameError.timeout.isConnectivity)
        XCTAssertFalse(FrameError.unauthorized.isConnectivity)
    }
}

final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest, Data?) -> Result<(Int, Data), URLError>)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                collected.append(buffer, count: read)
            }
            stream.close()
            body = collected
        }
        switch Self.handler?(request, body) {
        case .success(let (status, data)):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
        }
    }
}

final class URLSessionTransportTests: XCTestCase {
    private func api() -> FrameAPI {
        let configuration = URLSessionTransport.lanConfiguration
        configuration.protocolClasses = [StubProtocol.self]
        return makeAPI(URLSessionTransport(.pinned(String(repeating: "a", count: 64)), configuration: configuration))
    }

    override func tearDown() {
        StubProtocol.handler = nil
    }

    func testJSONRequestTravelsThroughURLSession() async throws {
        nonisolated(unsafe) var seen: (URLRequest, Data?)?
        StubProtocol.handler = { request, body in
            seen = (request, body)
            return .success((200, Data(##"{"rev":2,"item":{"id":"s1","name":"Milk","qty":2,"note":"","done":false}}"##.utf8)))
        }
        let result = try await api().addItem(ShoppingDraft(name: "Milk", qty: 2))
        XCTAssertEqual(result.item?.name, "Milk")
        XCTAssertEqual(seen?.0.httpMethod, "POST")
        XCTAssertEqual(seen?.0.url?.path, "/v1/shopping")
        XCTAssertEqual(seen?.0.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let body = try XCTUnwrap(seen?.1)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? NSDictionary, ["name": "Milk", "qty": 2])
    }

    func testNotModifiedThroughURLSession() async throws {
        StubProtocol.handler = { _, _ in .success((304, Data())) }
        let state = try await api().state(since: 4)
        XCTAssertNil(state)
    }

    func testErrorEnvelopeThroughURLSession() async {
        StubProtocol.handler = { _, _ in .success((409, Data(##"{"error":{"code":"conflict","message":"Already there"}}"##.utf8))) }
        do {
            _ = try await api().state()
            XCTFail("expected conflict")
        } catch {
            XCTAssertEqual(error as? FrameError, .api(status: 409, code: "conflict"))
        }
    }

    func testTimeoutThroughURLSession() async {
        StubProtocol.handler = { _, _ in .failure(URLError(.timedOut)) }
        do {
            _ = try await api().state()
            XCTFail("expected timeout")
        } catch {
            XCTAssertEqual(error as? FrameError, .timeout)
        }
    }

    func testCancelledTaskSurfacesAsCancelled() async {
        StubProtocol.handler = { _, _ in
            Thread.sleep(forTimeInterval: 0.5)
            return .success((200, Data(##"{"rev":1}"##.utf8)))
        }
        let client = api()
        let task = Task { try await client.state() }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertEqual(error as? FrameError, .cancelled)
        }
    }
}
