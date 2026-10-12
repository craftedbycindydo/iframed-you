import XCTest
@testable import SkylitCore

@MainActor
final class PairingFlowTests: XCTestCase {
    private func flow(_ transport: HTTPTransport, tokens: TokenStoring = InMemoryTokenStore()) -> PairingFlow {
        PairingFlow(frameName: "Kitchen", api: makeAPI(transport, token: nil), deviceName: "Test phone", tokens: tokens)
    }

    func testHappyPathStoresTokenUnderFrameId() async {
        let tokens = InMemoryTokenStore()
        let transport = ScriptedTransport([.status(204, ""), .status(200, #"{"token":"abc123","frameId":"f-9","name":"Kitchen"}"#)])
        let pairing = flow(transport, tokens: tokens)
        XCTAssertEqual(pairing.step, .idle)
        await pairing.start()
        XCTAssertEqual(pairing.step, .awaitingCode)
        let result = await pairing.submit(code: "123456")
        XCTAssertEqual(pairing.step, .paired)
        XCTAssertEqual(result?.frameId, "f-9")
        XCTAssertEqual(tokens.token(for: "f-9"), "abc123")
        XCTAssertEqual(transport.calls.map { $0.request.url!.path }, ["/v1/pair/start", "/v1/pair/finish"])
        XCTAssertEqual(transport.calls[1].json, ["code": "123456", "deviceName": "Test phone"])
    }

    func testStartFailureIsReported() async {
        let pairing = flow(ScriptedTransport([.failure(URLError(.cannotConnectToHost))]))
        await pairing.start()
        XCTAssertEqual(pairing.step, .failed)
        XCTAssertEqual(pairing.message, FrameError.offline.userMessage)
    }

    func testMalformedCodesNeverReachTheFrame() async {
        let transport = ScriptedTransport([.status(204, "")])
        let pairing = flow(transport)
        await pairing.start()
        for code in ["", "12345", "1234567", "12a456", "١٢٣٤٥٦"] {
            let result = await pairing.submit(code: code)
            XCTAssertNil(result)
        }
        XCTAssertEqual(pairing.step, .awaitingCode)
        XCTAssertNotNil(pairing.message)
        XCTAssertEqual(transport.calls.count, 1)
    }

    func testSubmitBeforeStartDoesNothing() async {
        let transport = ScriptedTransport()
        let result = await flow(transport).submit(code: "123456")
        XCTAssertNil(result)
        XCTAssertTrue(transport.calls.isEmpty)
    }

    func testWrongCodeAllowsAnotherAttempt() async {
        let tokens = InMemoryTokenStore()
        let transport = ScriptedTransport([
            .status(204, ""),
            .status(401, #"{"error":{"code":"unauthorized","message":"That code is not correct."}}"#),
            .status(200, #"{"token":"t","frameId":"f","name":"Kitchen"}"#),
        ])
        let pairing = flow(transport, tokens: tokens)
        await pairing.start()
        let first = await pairing.submit(code: "000000")
        XCTAssertNil(first)
        XCTAssertEqual(pairing.step, .awaitingCode)
        XCTAssertEqual(pairing.message, "That code didn't match. Check the frame and try again.")
        XCTAssertNil(tokens.token(for: "f"))
        let second = await pairing.submit(code: "123456")
        XCTAssertNotNil(second)
        XCTAssertNil(pairing.message)
    }

    func testExpiredCodeNeedsANewStart() async {
        let pairing = flow(ScriptedTransport([.status(204, ""), .status(409, #"{"error":{"code":"conflict","message":"No pairing code is active. Start pairing again."}}"#)]))
        await pairing.start()
        _ = await pairing.submit(code: "123456")
        XCTAssertEqual(pairing.step, .failed)
        XCTAssertEqual(pairing.message, "No pairing code is active. Start pairing again.")
    }

    func testStartRateLimitAsksToTryLater() async {
        let pairing = flow(ScriptedTransport([.status(429, #"{"error":{"code":"rate_limited","message":"Too many pairing attempts. Try again later."}}"#)]))
        await pairing.start()
        XCTAssertEqual(pairing.step, .failed)
        XCTAssertEqual(pairing.message, "Too many pairing attempts. Try again later.")
    }

    func testDeviceNameIsTrimmedToTheContractLimit() async {
        let transport = ScriptedTransport([.status(204, ""), .status(200, #"{"token":"t","frameId":"f","name":"Kitchen"}"#)])
        let pairing = PairingFlow(frameName: "Kitchen", api: makeAPI(transport, token: nil), deviceName: String(repeating: "n", count: 200), tokens: InMemoryTokenStore())
        await pairing.start()
        _ = await pairing.submit(code: "123456")
        XCTAssertEqual((transport.calls[1].json?["deviceName"] as? String)?.count, 80)
        let unnamed = PairingFlow(frameName: "Kitchen", api: makeAPI(transport, token: nil), deviceName: "  ", tokens: InMemoryTokenStore())
        await unnamed.start()
        _ = await unnamed.submit(code: "123456")
        XCTAssertEqual(transport.calls[3].json?["deviceName"] as? String, "iPhone")
    }

    func testRateLimitEndsTheAttemptAndRestartRequestsANewCode() async {
        let transport = ScriptedTransport([
            .status(204, ""),
            .status(429, #"{"error":{"code":"rate_limited","message":"Too many wrong codes. Start pairing again later."}}"#),
            .status(204, ""),
        ])
        let pairing = flow(transport)
        await pairing.start()
        _ = await pairing.submit(code: "000000")
        XCTAssertEqual(pairing.step, .failed)
        XCTAssertEqual(pairing.message, "Too many wrong codes. Start pairing again later.")
        let blocked = await pairing.submit(code: "123456")
        XCTAssertNil(blocked)
        XCTAssertEqual(transport.calls.count, 2)
        await pairing.start()
        XCTAssertEqual(pairing.step, .awaitingCode)
        XCTAssertNil(pairing.message)
    }

    func testNetworkDropWhileVerifyingKeepsCodeEntryOpen() async {
        let pairing = flow(ScriptedTransport([.status(204, ""), .failure(URLError(.timedOut))]))
        await pairing.start()
        _ = await pairing.submit(code: "123456")
        XCTAssertEqual(pairing.step, .awaitingCode)
        XCTAssertEqual(pairing.message, FrameError.timeout.userMessage)
    }

    func testAgainstDemoFrameFiveWrongCodesThenLockout() async {
        let server = DemoFrameServer()
        let pairing = flow(server)
        await pairing.start()
        for _ in 0..<4 {
            _ = await pairing.submit(code: "000000")
            XCTAssertEqual(pairing.step, .awaitingCode)
        }
        _ = await pairing.submit(code: "000000")
        XCTAssertEqual(pairing.step, .failed)
        XCTAssertEqual(server.requests.filter { $0.path == "/v1/pair/finish" }.count, 5)
        await pairing.start()
        let result = await pairing.submit(code: server.pairingCode)
        XCTAssertEqual(result?.frameId, "demo-frame")
        XCTAssertEqual(result?.token.count, 64)
    }
}

final class TokenStoreTests: XCTestCase {
    func testInMemoryStoreIsKeyedByFrame() {
        let store = InMemoryTokenStore()
        XCTAssertNil(store.token(for: "a"))
        store.save("one", for: "a")
        store.save("two", for: "b")
        XCTAssertEqual(store.token(for: "a"), "one")
        XCTAssertEqual(store.token(for: "b"), "two")
        store.save("three", for: "a")
        XCTAssertEqual(store.token(for: "a"), "three")
        store.removeToken(for: "a")
        XCTAssertNil(store.token(for: "a"))
        XCTAssertEqual(store.token(for: "b"), "two")
    }

    func testKeychainStoreRoundTrip() throws {
        let store = KeychainTokenStore(service: "com.iframed.you.tests.\(UUID().uuidString)")
        store.save("secret-1", for: "frame-a")
        defer { store.removeToken(for: "frame-a") }
        try XCTSkipIf(store.token(for: "frame-a") == nil, "No keychain available to this test process")
        XCTAssertEqual(store.token(for: "frame-a"), "secret-1")
        XCTAssertNil(store.token(for: "frame-b"))
        store.save("secret-2", for: "frame-a")
        XCTAssertEqual(store.token(for: "frame-a"), "secret-2")
        store.removeToken(for: "frame-a")
        XCTAssertNil(store.token(for: "frame-a"))
    }

    func testPairedFrameStorePersistsIdentityButNoAddress() throws {
        let defaults = isolatedDefaults()
        let store = PairedFrameStore(defaults: defaults)
        XCTAssertNil(store.current)
        store.current = PairedFrame(frameId: "f1", name: "Kitchen")
        XCTAssertEqual(PairedFrameStore(defaults: defaults).current, PairedFrame(frameId: "f1", name: "Kitchen"))
        let saved = try XCTUnwrap(defaults.data(forKey: "skylit.pairedFrame"))
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any]).keys.sorted()
        XCTAssertEqual(keys, ["frameId", "name"])
        store.current = nil
        XCTAssertNil(store.current)
    }
}
