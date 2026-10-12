import XCTest
@testable import SkylitCore

final class PinTests: XCTestCase {
    private let pin = String(repeating: "ab", count: 32)

    func testHexValidation() {
        XCTAssertTrue(Hex.isValid(pin, bytes: 32))
        XCTAssertTrue(Hex.isValid("00ff", bytes: 2))
        for refused in ["", "0", "00f", "00fF", "00FG", "00fg", " 0ff", "00ff ", "٠٠ff", "00ff00"] {
            XCTAssertFalse(Hex.isValid(refused, bytes: 2), refused)
            XCTAssertNil(Hex.decode(refused, bytes: 2), refused)
        }
        XCTAssertEqual(Hex.decode("00ff", bytes: 2), Data([0x00, 0xFF]))
        XCTAssertEqual(Hex.encode(Data([0x00, 0x0A, 0xFF])), "000aff")
        XCTAssertEqual(Hex.decode(Hex.encode(Data(0...255)), bytes: 256), Data(0...255))
    }

    func testFingerprintIsSHA256OfTheCertificateBytes() {
        XCTAssertEqual(Pin.fingerprint(ofCertificate: Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(Pin.frameId(for: pin), String(repeating: "ab", count: 16))
    }

    func testPinComparison() {
        XCTAssertTrue(Pin.matches(pin, pin: pin))
        XCTAssertFalse(Pin.matches(String(pin.dropLast()) + "c", pin: pin))
        XCTAssertFalse(Pin.matches(String(pin.prefix(32)), pin: pin))
        XCTAssertFalse(Pin.matches(pin.uppercased(), pin: pin))
        XCTAssertFalse(Pin.matches("", pin: ""))
        XCTAssertFalse(Pin.matches(pin.uppercased(), pin: pin.uppercased()))
        XCTAssertTrue(PairingCrypto.constantTimeEquals("123456", "123456"))
        XCTAssertFalse(PairingCrypto.constantTimeEquals("123456", "123457"))
        XCTAssertFalse(PairingCrypto.constantTimeEquals("123456", "12345"))
    }

    func testTrustDecisions() {
        let mine = Data("frame certificate".utf8), other = Data("another certificate".utf8)
        let pinned = TrustGate(.pinned(Pin.fingerprint(ofCertificate: mine)))
        XCTAssertFalse(pinned.accepts(leaf: other))
        XCTAssertNil(pinned.fingerprint)
        XCTAssertTrue(pinned.accepts(leaf: mine))
        XCTAssertFalse(pinned.accepts(leaf: other))
        XCTAssertFalse(TrustGate(.pinned("")).accepts(leaf: mine))
        XCTAssertFalse(TrustGate(.pinned("not a pin")).accepts(leaf: mine))

        let probe = TrustGate(.probe)
        XCTAssertNil(probe.fingerprint)
        XCTAssertTrue(probe.accepts(leaf: other))
        XCTAssertEqual(probe.fingerprint, Pin.fingerprint(ofCertificate: other))
        XCTAssertTrue(probe.accepts(leaf: mine))
        XCTAssertEqual(probe.fingerprint, Pin.fingerprint(ofCertificate: mine))

        let pairing = TrustGate(.pairing)
        XCTAssertTrue(pairing.accepts(leaf: mine))
        XCTAssertFalse(pairing.accepts(leaf: other))
        XCTAssertTrue(pairing.accepts(leaf: mine))
        XCTAssertEqual(pairing.fingerprint, Pin.fingerprint(ofCertificate: mine))
    }

    func testResponseLimitsByRoute() {
        func limit(_ method: String, _ path: String) -> Int {
            var request = URLRequest(url: URL(string: "https://192.168.1.20:8765\(path)")!)
            request.httpMethod = method
            return Limits.responseBytes(for: request)
        }
        XCTAssertEqual(limit("GET", "/v1/photos/abc"), 16 * 1024 * 1024)
        XCTAssertEqual(limit("GET", "/v1/photos"), 1024 * 1024)
        XCTAssertEqual(limit("POST", "/v1/photos"), 1024 * 1024)
        XCTAssertEqual(limit("DELETE", "/v1/photos/abc"), 1024 * 1024)
        XCTAssertEqual(limit("GET", "/v2/info"), 1024 * 1024)
    }
}

final class TLSTransportTests: XCTestCase {
    private static let state = ##"{"rev":7}"##

    private func frame(_ respond: @escaping @Sendable (String) -> Data = { _ in TLSTestServer.json("200 OK", TLSTransportTests.state) }) async throws -> TLSTestServer {
        try await TLSTestServer(try TestIdentity.make(), respond: respond)
    }

    private func attempt(_ call: () async throws -> Void) async -> FrameError? {
        do {
            try await call()
            return nil
        } catch {
            return error as? FrameError
        }
    }

    func testMatchingCertificateCarriesTheRequest() async throws {
        let server = try await frame()
        let transport = URLSessionTransport(.pinned(server.fingerprint))
        let state = try await FrameAPI(baseURL: server.url, token: "sesame", transport: transport).state()
        XCTAssertEqual(state?.rev, 7)
        XCTAssertEqual(transport.fingerprint, server.fingerprint)
        XCTAssertTrue(server.requests[0].hasPrefix("GET /v1/state HTTP/1.1"))
        XCTAssertTrue(server.requests[0].contains("Bearer sesame"))
        XCTAssertFalse(server.requests[0].lowercased().contains("cookie"))
        XCTAssertTrue(server.requests[0].contains("User-Agent: iFramedYou\r\n"))
        XCTAssertFalse(server.requests[0].contains("Skylit"))
    }

    func testWrongCertificateReceivesNoRequestBytes() async throws {
        let server = try await frame()
        let api = FrameAPI(baseURL: server.url, token: "sesame", transport: URLSessionTransport(.pinned(String(repeating: "0", count: 64))))
        let getError = await attempt { _ = try await api.state() }
        XCTAssertEqual(getError, .pinMismatch)
        let postError = await attempt { _ = try await api.addItem(ShoppingDraft(name: "Milk")) }
        XCTAssertEqual(postError, .pinMismatch)
        let uploadError = await attempt { _ = try await api.uploadPhoto(Data([0xFF, 0xD8, 0xFF])) }
        XCTAssertEqual(uploadError, .pinMismatch)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertGreaterThanOrEqual(server.connections, 1)
        XCTAssertEqual(server.applicationBytes, 0)
    }

    func testProbeReportsTheFingerprintAndDoesNotUnlockThePinnedPool() async throws {
        let server = try await frame { _ in TLSTestServer.json("200 OK", ##"{"v":2,"frameId":"f","name":"Kitchen","pairing":false}"##) }
        let probe = URLSessionTransport(.probe)
        let info = try await FrameAPI(baseURL: server.url, transport: probe).info()
        XCTAssertEqual(info.name, "Kitchen")
        XCTAssertEqual(probe.fingerprint, server.fingerprint)
        XCTAssertFalse(server.requests[0].contains("Authorization"))
        let seen = server.applicationBytes
        for _ in 0..<3 {
            let pinned = FrameAPI(baseURL: server.url, token: "sesame", transport: URLSessionTransport(.pinned(String(repeating: "0", count: 64))))
            let error = await attempt { _ = try await pinned.state() }
            XCTAssertEqual(error, .pinMismatch)
        }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(server.applicationBytes, seen)
    }

    func testAcceptedConnectionDoesNotUnlockALaterWrongCertificateOnTheSamePool() async throws {
        let real = try await frame()
        let other = try await frame()
        let api = FrameAPI(baseURL: real.url, token: "sesame", transport: URLSessionTransport(.pinned(real.fingerprint)))
        _ = try await api.state()
        var moved = api
        moved.baseURL = other.url
        let error = await attempt { _ = try await moved.state() }
        XCTAssertEqual(error, .pinMismatch)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(other.applicationBytes, 0)
        _ = try await api.state()
    }

    func testPairingPoolHoldsTheFirstCertificateForTheWholeAttempt() async throws {
        let real = try await frame { _ in TLSTestServer.json("200 OK", ##"{"session":"s","nF":"n"}"##) }
        let other = try await frame()
        let transport = URLSessionTransport(.pairing)
        _ = try await FrameAPI(baseURL: real.url, transport: transport).pairStart(commit: "c", tokenHash: "h", deviceName: "Phone")
        XCTAssertEqual(transport.fingerprint, real.fingerprint)
        let api = FrameAPI(baseURL: other.url, transport: transport)
        let error = await attempt { try await api.pairReveal(session: "s", nP: "secret-nonce") }
        XCTAssertEqual(error, .pinMismatch)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(other.applicationBytes, 0)
        XCTAssertEqual(transport.fingerprint, real.fingerprint)
    }

    func testRedirectsAreRefused() async throws {
        let elsewhere = try await frame()
        let target = elsewhere.url.absoluteString
        let server = try await frame { head in
            head.hasPrefix("GET /v1/state") ? TLSTestServer.json("307 Temporary Redirect", "", extra: "Location: \(target)/v1/state\r\n")
                : TLSTestServer.json("302 Found", "", extra: "Location: /v2/info\r\n")
        }
        let api = FrameAPI(baseURL: server.url, token: "sesame", transport: URLSessionTransport(.pinned(server.fingerprint)))
        let crossHost = await attempt { _ = try await api.state() }
        XCTAssertEqual(crossHost, .api(status: 307, code: "http_307"))
        let sameHost = await attempt { _ = try await api.photos() }
        XCTAssertEqual(sameHost, .api(status: 302, code: "http_302"))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(server.connections, 2)
        XCTAssertEqual(elsewhere.connections, 0)
    }

    func testResponsesOverTheCapAreDropped() async throws {
        let declared = try await frame { _ in
            Data("HTTP/1.1 200 OK\r\nContent-Length: \(Limits.jsonResponseBytes + 1)\r\nConnection: close\r\n\r\n".utf8) + Data(count: Limits.jsonResponseBytes + 1)
        }
        let declaredError = await attempt { _ = try await FrameAPI(baseURL: declared.url, transport: URLSessionTransport(.probe)).info() }
        XCTAssertEqual(declaredError, .invalidResponse)

        let streamed = try await frame { _ in
            Data("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n".utf8) + Data(repeating: 0x20, count: Limits.jsonResponseBytes + 1)
        }
        let streamedError = await attempt { _ = try await FrameAPI(baseURL: streamed.url, transport: URLSessionTransport(.probe)).info() }
        XCTAssertEqual(streamedError, .invalidResponse)

        let photo = try await frame { _ in
            Data("HTTP/1.1 200 OK\r\nContent-Length: \(Limits.jsonResponseBytes + 1)\r\nConnection: close\r\n\r\n".utf8) + Data(repeating: 0xFF, count: Limits.jsonResponseBytes + 1)
        }
        let api = FrameAPI(baseURL: photo.url, token: "sesame", transport: URLSessionTransport(.pinned(photo.fingerprint)))
        let picture = try await api.photoData(id: "abc")
        XCTAssertEqual(picture.count, Limits.jsonResponseBytes + 1)
        let listError = await attempt { _ = try await api.photos() }
        XCTAssertEqual(listError, .invalidResponse)
    }

    func testPlainHTTPNeverLeavesThePhone() async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:9/v2/info")!)
        request.setValue("Bearer sesame", forHTTPHeaderField: "Authorization")
        do {
            _ = try await URLSessionTransport(.probe).send(request, body: nil, onProgress: nil)
            XCTFail("expected refusal")
        } catch {
            XCTAssertEqual(error as? FrameError, .offline)
        }
    }

    func testUploadReportsProgressOverTLS() async throws {
        let server = try await frame { _ in TLSTestServer.json("200 OK", ##"{"rev":8,"photo":{"id":"aa","addedAt":"2026-10-11T10:00:00Z"}}"##) }
        let api = FrameAPI(baseURL: server.url, token: "sesame", transport: URLSessionTransport(.pinned(server.fingerprint)))
        let finished = expectation(description: "progress")
        finished.assertForOverFulfill = false
        let result = try await api.uploadPhoto(Data([0xFF, 0xD8] + [UInt8](repeating: 7, count: 200_000))) { fraction in
            if fraction == 1 { finished.fulfill() }
        }
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(result.photo?.id, "aa")
        XCTAssertGreaterThan(server.applicationBytes, 200_000)
    }
}
