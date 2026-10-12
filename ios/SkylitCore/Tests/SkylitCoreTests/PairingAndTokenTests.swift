import XCTest
import Security
@testable import SkylitCore

final class PairingCryptoTests: XCTestCase {
    func testContractVector() throws {
        let nP = try XCTUnwrap(Hex.decode("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f", bytes: 32))
        let nF = try XCTUnwrap(Hex.decode("202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f", bytes: 32))
        let fpRaw = try XCTUnwrap(Hex.decode("404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f", bytes: 32))
        XCTAssertEqual(PairingCrypto.sha256(nP), "630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd")
        let derived = PairingCrypto.derive(nP: nP, nF: nF, fpRaw: fpRaw)
        XCTAssertEqual(Hex.encode(derived.digest), "526438df18ab2fc054b103a87964836abe6e20d4118d11b6a6e50ebbca57d7af")
        XCTAssertEqual(derived.code, "299871")
        XCTAssertEqual(derived.pick, "64")
    }

    func testDerivationDependsOnEveryInputAndTheirOrder() {
        let a = Data(repeating: 1, count: 32), b = Data(repeating: 2, count: 32), c = Data(repeating: 3, count: 32)
        let base = PairingCrypto.derive(nP: a, nF: b, fpRaw: c).digest
        XCTAssertNotEqual(base, PairingCrypto.derive(nP: b, nF: a, fpRaw: c).digest)
        XCTAssertNotEqual(base, PairingCrypto.derive(nP: a, nF: c, fpRaw: b).digest)
        XCTAssertNotEqual(base, PairingCrypto.derive(nP: a, nF: b, fpRaw: a).digest)
        XCTAssertEqual(base, PairingCrypto.derive(nP: a, nF: b, fpRaw: c).digest)
    }

    func testCodeAndPickAreAlwaysZeroPaddedDigits() throws {
        var sawLeadingZero = false
        for seed in 0..<400 {
            let derived = PairingCrypto.derive(nP: Data(repeating: UInt8(seed % 256), count: 32), nF: Data(repeating: UInt8(seed / 256), count: 32),
                                               fpRaw: Data(repeating: 9, count: 32))
            XCTAssertTrue(PairingFlow.isValid(code: derived.code), derived.code)
            XCTAssertEqual(derived.pick.utf8.count, 2)
            XCTAssertTrue(derived.pick.utf8.allSatisfy { (48...57).contains($0) })
            let head = derived.digest.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            XCTAssertEqual(UInt32(derived.code), head % 1_000_000)
            sawLeadingZero = sawLeadingZero || derived.code.hasPrefix("0") || derived.pick.hasPrefix("0")
        }
        XCTAssertTrue(sawLeadingZero)
    }

    func testRandomBytesAreFreshAndTheRightLength() throws {
        let first = try PairingCrypto.randomBytes(), second = try PairingCrypto.randomBytes()
        XCTAssertEqual(first.count, 32)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try PairingCrypto.randomBytes(16).count, 16)
    }

    func testCodeShape() {
        XCTAssertTrue(PairingFlow.isValid(code: "012345"))
        for refused in ["", "12345", "1234567", "12a456", "١٢٣٤٥٦", "12 456"] {
            XCTAssertFalse(PairingFlow.isValid(code: refused), refused)
        }
    }
}

@MainActor
final class PairingFlowTests: XCTestCase {
    private var server: DemoFrameServer!
    private var network: DemoNetwork!
    private var tokens: InMemoryTokenStore!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        server = DemoFrameServer()
        server.openPairingWindow()
        network = DemoNetwork(server)
        tokens = InMemoryTokenStore()
        defaults = isolatedDefaults()
    }

    private func makeFlow(patience: Duration = .seconds(5)) -> PairingFlow {
        let transport = network.pairing()
        return PairingFlow(frameName: "Kitchen", api: FrameAPI(baseURL: DemoFrameServer.address, transport: transport),
                           probe: FrameAPI(baseURL: DemoFrameServer.address, transport: network.probe()),
                           fingerprint: { transport.fingerprint }, tokens: tokens,
                           names: DeviceNameStore(defaults: defaults, fallback: "Test phone"), pollInterval: .milliseconds(1), patience: patience)
    }

    private func scripted(probe: [ScriptedTransport.Reply], api: ScriptedTransport, fingerprint: String? = String(repeating: "ab", count: 32)) -> PairingFlow {
        PairingFlow(frameName: "Kitchen", api: makeAPI(api, token: nil), probe: makeAPI(ScriptedTransport(probe), token: nil),
                    fingerprint: { fingerprint }, tokens: tokens, names: DeviceNameStore(defaults: defaults), pollInterval: .milliseconds(1))
    }

    private let open = ScriptedTransport.Reply.status(200, ##"{"v":2,"frameId":"f","name":"Kitchen","pairing":true}"##)

    private func wrongCode() throws -> String {
        try XCTUnwrap(server.shownCode) == "000000" ? "111111" : "000000"
    }

    private func paths() -> [String] {
        server.requests.map(\.path)
    }

    private func assertFailed(_ flow: PairingFlow, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(flow.step, .failed, file: file, line: line)
        XCTAssertEqual(flow.message, "This phone did not pair. Another device may be trying. Tap Cancel on the frame; do not tap a number.", file: file, line: line)
        XCTAssertNil(tokens.credential(for: server.frameId), file: file, line: line)
    }

    func testHappyPathKeepsTheTokenOnThePhoneUntilTheFrameApproves() async throws {
        let flow = makeFlow()
        XCTAssertEqual(flow.step, .naming)
        await flow.begin(name: "  Maya's iPhone ")
        XCTAssertEqual(flow.step, .enteringCode)
        XCTAssertEqual(paths(), ["/v2/info", "/v2/pair/start", "/v2/pair/reveal"])
        let start = try XCTUnwrap(server.requests[1].body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        XCTAssertEqual(Set(start.keys), ["commit", "tokenHash", "deviceName"])
        XCTAssertEqual(start["deviceName"], "Maya's iPhone")
        let reveal = try XCTUnwrap(server.requests[2].body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        XCTAssertEqual(PairingCrypto.sha256(try XCTUnwrap(Hex.decode(reveal["nP"] ?? "", bytes: 32))), start["commit"])

        await flow.submit(code: try XCTUnwrap(server.shownCode))
        XCTAssertEqual(flow.step, .confirming(pick: try XCTUnwrap(server.shownPick)))
        XCTAssertEqual(PairingFlow.tapText("07"), "Tap 07 on the frame")
        XCTAssertNil(tokens.credential(for: server.frameId))

        let result = await flow.awaitResult()
        XCTAssertEqual(flow.step, .paired)
        XCTAssertEqual(result?.frame, PairedFrame(frameId: server.frameId, name: "Kitchen frame"))
        let credential = try XCTUnwrap(tokens.credential(for: server.frameId))
        XCTAssertEqual(credential, result?.credential)
        XCTAssertEqual(credential.fp, server.fingerprint)
        XCTAssertEqual(PairingCrypto.sha256(try XCTUnwrap(Hex.decode(credential.token, bytes: 32))), start["tokenHash"])
        for request in server.requests {
            XCTAssertNil(request.headers["Authorization"])
            XCTAssertFalse(String(decoding: request.body ?? Data(), as: UTF8.self).contains(credential.token))
            XCTAssertFalse((request.query ?? "").contains(credential.token))
        }
        XCTAssertFalse(paths().contains("/v2/pair/cancel"))
        let state = try await FrameAPI(baseURL: DemoFrameServer.address, token: credential.token, transport: network.pinned(credential.fp)).state()
        XCTAssertNotNil(state)
    }

    func testEveryAttemptUsesFreshSecrets() async throws {
        await makeFlow().begin(name: "Phone")
        server.openPairingWindow()
        await makeFlow().begin(name: "Phone")
        let starts = try server.requests.filter { $0.path == "/v2/pair/start" }
            .map { try XCTUnwrap(JSONSerialization.jsonObject(with: $0.body ?? Data()) as? [String: String]) }
        XCTAssertEqual(starts.count, 2)
        XCTAssertNotEqual(starts[0]["commit"], starts[1]["commit"])
        XCTAssertNotEqual(starts[0]["tokenHash"], starts[1]["tokenHash"])
    }

    func testNameIsRequiredAndRemembered() async {
        let flow = makeFlow()
        XCTAssertEqual(flow.suggestedName, "Test phone")
        for refused in ["", "   ", String(repeating: "n", count: 41), "Karan\u{202E}enohPi"] {
            await flow.begin(name: refused)
            XCTAssertEqual(flow.step, .naming)
            XCTAssertEqual(flow.message, "Give this phone a name of 1 to 40 characters.")
        }
        XCTAssertTrue(server.requests.isEmpty)
        await flow.begin(name: "Hallway phone")
        XCTAssertEqual(flow.step, .enteringCode)
        XCTAssertEqual(makeFlow().suggestedName, "Hallway phone")
    }

    func testClosedWindowAsksForATapOnTheFrameAndSendsNothingElse() async {
        server = DemoFrameServer()
        network = DemoNetwork(server)
        let flow = makeFlow()
        await flow.begin(name: "Phone")
        XCTAssertEqual(flow.step, .naming)
        XCTAssertEqual(flow.message, PairingFlow.windowText)
        XCTAssertEqual(paths(), ["/v2/info"])
        server.openPairingWindow()
        await flow.begin(name: "Phone")
        XCTAssertEqual(flow.step, .enteringCode)
    }

    func testNoWindowAtStartIsCalmAndStaysOnTheNameStep() async {
        let api = ScriptedTransport([.status(409, ##"{"error":{"code":"conflict","message":"x"}}"##)])
        let flow = scripted(probe: [open, open], api: api)
        await flow.begin(name: "Phone")
        XCTAssertEqual(flow.step, .naming)
        XCTAssertEqual(flow.message, PairingFlow.windowText)
        XCTAssertFalse(flow.message?.contains("Another device") ?? true)
        XCTAssertEqual(api.calls.map { $0.request.url!.path }, ["/v2/pair/start"])
        api.queue(.status(200, ##"{"session":"\##(String(repeating: "5", count: 32))","nF":"\##(String(repeating: "6", count: 64))"}"##))
        api.queue(.status(204, ""))
        await flow.begin(name: "Phone")
        XCTAssertEqual(flow.step, .enteringCode)
    }

    func testWindowRunningOutAtRevealIsATimeout() async {
        let api = ScriptedTransport([
            .status(200, ##"{"session":"\##(String(repeating: "5", count: 32))","nF":"\##(String(repeating: "6", count: 64))"}"##),
            .status(410, ##"{"error":{"code":"gone","message":"x"}}"##),
            .status(204, ""),
        ])
        let flow = scripted(probe: [open], api: api)
        await flow.begin(name: "Phone")
        XCTAssertEqual(flow.step, .failed)
        XCTAssertEqual(flow.message, PairingFlow.timeoutText)
        XCTAssertEqual(api.calls.map { $0.request.url!.path }, ["/v2/pair/start", "/v2/pair/reveal", "/v2/pair/cancel"])
    }

    func testEveryEndingHasItsOwnWordingAndNoneLeaksTheCode() {
        let texts = [PairingFlow.failureText, PairingFlow.timeoutText, PairingFlow.windowText, PairingFlow.cancelledText]
        XCTAssertEqual(Set(texts).count, texts.count)
        XCTAssertTrue(PairingFlow.failureText.contains("Another device"))
        for calm in [PairingFlow.timeoutText, PairingFlow.windowText, PairingFlow.cancelledText] {
            XCTAssertFalse(calm.contains("Another device"), calm)
            XCTAssertTrue(calm.lowercased().contains("try again"), calm)
        }
    }

    func testBusyWindowAtStartIsAFailureWithNothingToCancel() async {
        let api = ScriptedTransport([.status(409, ##"{"error":{"code":"pairing_busy","message":"x"}}"##)])
        let flow = scripted(probe: [open], api: api)
        await flow.begin(name: "Phone")
        assertFailed(flow)
        XCTAssertEqual(api.calls.map { $0.request.url!.path }, ["/v2/pair/start"])
        await flow.begin(name: "Phone")
        await flow.submit(code: "123456")
        XCTAssertEqual(api.calls.count, 1)
    }

    func testSecondPhoneFindsTheWindowUsed() async throws {
        await makeFlow().begin(name: "First phone")
        let second = makeFlow()
        await second.begin(name: "Second phone")
        XCTAssertEqual(second.step, .naming)
        XCTAssertEqual(second.message, PairingFlow.windowText)
        let direct = FrameAPI(baseURL: DemoFrameServer.address, transport: network.pairing())
        do {
            _ = try await direct.pairStart(commit: String(repeating: "a", count: 64), tokenHash: String(repeating: "b", count: 64), deviceName: "Third")
            XCTFail("expected pairing_busy")
        } catch {
            XCTAssertEqual(error as? FrameError, .api(status: 409, code: "pairing_busy"))
        }
    }

    func testUnreachableFrameAtStartCanBeTriedAgainByThePerson() async {
        let api = ScriptedTransport([.failure(URLError(.timedOut))])
        let flow = scripted(probe: [open], api: api)
        await flow.begin(name: "Phone")
        XCTAssertEqual(flow.step, .naming)
        XCTAssertEqual(flow.message, FrameError.timeout.userMessage)
        XCTAssertEqual(api.calls.count, 1)
    }

    func testMalformedRepliesAtStartFailAndCancel() async {
        let session = String(repeating: "5", count: 32), nF = String(repeating: "6", count: 64)
        let cases: [(String, String?, [String])] = [
            (##"{"session":"SHORT","nF":"\##(nF)"}"##, String(repeating: "ab", count: 32), ["/v2/pair/start"]),
            (##"{"session":"\##(session)","nF":"\##(nF.uppercased().replacingOccurrences(of: "6", with: "A"))"}"##, String(repeating: "ab", count: 32), ["/v2/pair/start", "/v2/pair/cancel"]),
            (##"{"session":"\##(session)","nF":"\##(nF)"}"##, nil, ["/v2/pair/start", "/v2/pair/cancel"]),
        ]
        for (reply, fingerprint, expected) in cases {
            let api = ScriptedTransport([.status(200, reply)])
            let flow = scripted(probe: [open], api: api, fingerprint: fingerprint)
            await flow.begin(name: "Phone")
            assertFailed(flow)
            XCTAssertEqual(api.calls.map { $0.request.url!.path }, expected)
        }
    }

    func testRevealRefusedFailsAndCancels() async {
        let api = ScriptedTransport([
            .status(200, ##"{"session":"\##(String(repeating: "5", count: 32))","nF":"\##(String(repeating: "6", count: 64))"}"##),
            .status(400, ##"{"error":{"code":"bad_request","message":"x"}}"##),
            .status(204, ""),
        ])
        let flow = scripted(probe: [open], api: api)
        await flow.begin(name: "Phone")
        assertFailed(flow)
        XCTAssertEqual(api.calls.map { $0.request.url!.path }, ["/v2/pair/start", "/v2/pair/reveal", "/v2/pair/cancel"])
        XCTAssertEqual(api.calls[2].json, ["session": String(repeating: "5", count: 32)])
    }

    func testThreeWrongCodesEndTheAttemptAndCancelOnTheFrame() async throws {
        let flow = makeFlow()
        await flow.begin(name: "Phone")
        let wrong = try wrongCode()
        for malformed in ["", "12345", "12a456"] {
            await flow.submit(code: malformed)
            XCTAssertEqual(flow.triesLeft, 3)
            XCTAssertEqual(flow.message, "Enter the 6-digit code shown on the frame.")
        }
        await flow.submit(code: wrong)
        XCTAssertEqual(flow.message, "That code didn't match. 2 tries left.")
        await flow.submit(code: wrong)
        XCTAssertEqual(flow.message, "That code didn't match. 1 try left.")
        XCTAssertEqual(flow.step, .enteringCode)
        XCTAssertFalse(paths().contains("/v2/pair/cancel"))
        await flow.submit(code: wrong)
        assertFailed(flow)
        XCTAssertEqual(paths().last, "/v2/pair/cancel")
        let before = server.requests.count
        await flow.submit(code: try XCTUnwrap(server.shownCode))
        let result = await flow.awaitResult()
        XCTAssertNil(result)
        await flow.begin(name: "Phone")
        XCTAssertEqual(flow.step, .failed)
        XCTAssertEqual(server.requests.count, before)
        XCTAssertFalse(flow.message?.contains(try XCTUnwrap(server.shownCode)) ?? true)
    }

    func testTwoWrongCodesThenTheRightOneStillPairs() async throws {
        let flow = makeFlow()
        await flow.begin(name: "Phone")
        await flow.submit(code: try wrongCode())
        await flow.submit(code: try wrongCode())
        await flow.submit(code: try XCTUnwrap(server.shownCode))
        XCTAssertNil(flow.message)
        let result = await flow.awaitResult()
        XCTAssertNotNil(result)
        XCTAssertEqual(flow.step, .paired)
    }

    private func confirming(_ bystander: DemoFrameServer.Bystander, patience: Duration = .seconds(5)) async throws -> PairingFlow {
        server.setBystander(bystander)
        let flow = makeFlow(patience: patience)
        await flow.begin(name: "Phone")
        await flow.submit(code: try XCTUnwrap(server.shownCode))
        return flow
    }

    func testDecoyOrCancelOnTheFrameEndsCalmly() async throws {
        for bystander in [DemoFrameServer.Bystander.tapsDecoy, .tapsCancel] {
            server.openPairingWindow()
            let flow = try await confirming(bystander)
            let result = await flow.awaitResult()
            XCTAssertNil(result)
            XCTAssertEqual(flow.step, .failed)
            XCTAssertEqual(flow.message, PairingFlow.cancelledText)
            XCTAssertNil(tokens.credential(for: server.frameId))
            XCTAssertEqual(paths().suffix(2), ["/v2/pair/result", "/v2/pair/cancel"])
        }
    }

    func testSessionForgottenByTheFrameEndsCalmly() async throws {
        let api = ScriptedTransport([
            .status(200, ##"{"session":"\##(String(repeating: "5", count: 32))","nF":"\##(String(repeating: "6", count: 64))"}"##),
            .status(204, ""),
        ])
        let flow = scripted(probe: [open], api: api)
        await flow.begin(name: "Phone")
        XCTAssertEqual(flow.step, .enteringCode)
        let revealed = try XCTUnwrap(api.calls[1].json?["nP"] as? String)
        let derived = PairingCrypto.derive(nP: try XCTUnwrap(Hex.decode(revealed, bytes: 32)),
                                           nF: Data(repeating: 0x66, count: 32),
                                           fpRaw: Data(repeating: 0xab, count: 32))
        await flow.submit(code: derived.code)
        XCTAssertEqual(flow.step, .confirming(pick: derived.pick))
        api.queue(.status(404, ##"{"error":{"code":"not_found","message":"x"}}"##))
        api.queue(.status(409, ##"{"error":{"code":"conflict","message":"x"}}"##))
        let result = await flow.awaitResult()
        XCTAssertNil(result)
        XCTAssertEqual(flow.step, .failed)
        XCTAssertEqual(flow.message, PairingFlow.cancelledText)
        XCTAssertEqual(api.calls.map { $0.request.url!.path }, ["/v2/pair/start", "/v2/pair/reveal", "/v2/pair/result", "/v2/pair/cancel"])
    }

    private func assertTimedOut(_ flow: PairingFlow, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(flow.step, .failed, file: file, line: line)
        XCTAssertEqual(flow.message, PairingFlow.timeoutText, file: file, line: line)
        XCTAssertFalse(flow.message?.contains("Another device") ?? true, file: file, line: line)
        XCTAssertNil(tokens.credential(for: server.frameId), file: file, line: line)
    }

    func testExpiryIsACalmTimeout() async throws {
        let flow = try await confirming(.letsItExpire)
        let result = await flow.awaitResult()
        XCTAssertNil(result)
        assertTimedOut(flow)
        XCTAssertEqual(paths().suffix(2), ["/v2/pair/result", "/v2/pair/cancel"])
    }

    func testWaitingStopsWhenPatienceRunsOutWithACalmTimeout() async throws {
        let flow = try await confirming(.waits, patience: .milliseconds(20))
        let result = await flow.awaitResult()
        XCTAssertNil(result)
        assertTimedOut(flow)
        XCTAssertEqual(paths().last, "/v2/pair/cancel")
        XCTAssertGreaterThan(paths().filter { $0 == "/v2/pair/result" }.count, 1)
    }

    func testTryAgainAfterAFailureStartsAFreshAttemptInTheSameSheet() async throws {
        let flow = try await confirming(.letsItExpire)
        _ = await flow.awaitResult()
        XCTAssertEqual(flow.step, .failed)
        flow.reset()
        XCTAssertEqual(flow.step, .naming)
        XCTAssertNil(flow.message)
        XCTAssertEqual(flow.triesLeft, PairingFlow.attempts)
        await flow.begin(name: "Phone")
        XCTAssertEqual(flow.message, PairingFlow.windowText)
        server.openPairingWindow()
        server.setBystander(.tapsPick)
        await flow.begin(name: "Phone")
        XCTAssertEqual(flow.step, .enteringCode)
        await flow.submit(code: try XCTUnwrap(server.shownCode))
        let result = await flow.awaitResult()
        XCTAssertNotNil(result)
        XCTAssertEqual(flow.step, .paired)
        XCTAssertNotNil(tokens.credential(for: server.frameId))
    }

    func testResetOnlyWorksAfterAFailure() async throws {
        let flow = makeFlow()
        await flow.begin(name: "Phone")
        flow.reset()
        XCTAssertEqual(flow.step, .enteringCode)
        await flow.submit(code: try XCTUnwrap(server.shownCode))
        flow.reset()
        XCTAssertEqual(flow.step, .confirming(pick: try XCTUnwrap(server.shownPick)))
    }

    func testCertificateChangeMidPairingSendsNothingToTheNewServer() async throws {
        let impostor = DemoFrameServer(identity: "impostor")
        let flow = try await confirming(.tapsPick)
        network.place(impostor, at: "demo-frame.local")
        let result = await flow.awaitResult()
        XCTAssertNil(result)
        assertFailed(flow)
        XCTAssertTrue(impostor.requests.isEmpty)
        XCTAssertFalse(paths().contains("/v2/pair/result"))
    }

    func testResultNamingAnotherFrameIsRejected() async throws {
        let flow = try await confirming(.tapsPick)
        server.claimFrameId(String(repeating: "f", count: 32))
        let result = await flow.awaitResult()
        XCTAssertNil(result)
        assertFailed(flow)
        XCTAssertNil(tokens.credential(for: String(repeating: "f", count: 32)))
        XCTAssertEqual(paths().last, "/v2/pair/cancel")
    }

    func testClosingTheSheetCancelsOnTheFrame() async throws {
        let flow = try await confirming(.waits)
        let waiting = Task { await flow.awaitResult() }
        try await Task.sleep(for: .milliseconds(20))
        await flow.abandon()
        let result = await waiting.value
        XCTAssertNil(result)
        XCTAssertEqual(flow.step, .failed)
        XCTAssertNil(flow.message)
        XCTAssertTrue(paths().contains("/v2/pair/cancel"))
        XCTAssertNil(tokens.credential(for: server.frameId))
    }

    func testANetworkBlipWhileWaitingDoesNotEndTheAttempt() async throws {
        let flow = try await confirming(.waits)
        let waiting = Task { await flow.awaitResult() }
        server.setUnreachable(true)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(flow.step, .confirming(pick: try XCTUnwrap(server.shownPick)))
        server.setUnreachable(false)
        server.setBystander(.tapsPick)
        let result = await waiting.value
        XCTAssertNotNil(result)
        XCTAssertEqual(flow.step, .paired)
    }
}

final class TokenStoreTests: XCTestCase {
    private let first = FrameCredential(token: String(repeating: "1", count: 64), fp: String(repeating: "a", count: 64))
    private let second = FrameCredential(token: String(repeating: "2", count: 64), fp: String(repeating: "b", count: 64))

    func testCredentialIsKeyedByThePin() {
        XCTAssertEqual(first.frameId, String(repeating: "a", count: 32))
        XCTAssertTrue(first.isValid)
        XCTAssertFalse(FrameCredential(token: "short", fp: first.fp).isValid)
        XCTAssertFalse(FrameCredential(token: first.token, fp: "demo-frame").isValid)
        XCTAssertFalse(FrameCredential(token: first.token, fp: first.fp.uppercased()).isValid)
    }

    func testInMemoryStoreIsKeyedByFrame() {
        let store = InMemoryTokenStore()
        XCTAssertNil(store.credential(for: first.frameId))
        store.save(first)
        store.save(second)
        store.save(FrameCredential(token: "bad", fp: "bad"))
        XCTAssertEqual(store.credential(for: first.frameId), first)
        XCTAssertEqual(store.credential(for: second.frameId), second)
        XCTAssertNil(store.credential(for: "bad"))
        store.remove(for: first.frameId)
        XCTAssertNil(store.credential(for: first.frameId))
        XCTAssertEqual(store.credential(for: second.frameId), second)
        XCTAssertFalse(store.removeLegacy())
    }

    func testKeychainStoreRoundTrip() throws {
        let store = KeychainTokenStore(service: "com.iframed.you.tests.\(UUID().uuidString)")
        store.save(first)
        defer { store.remove(for: first.frameId) }
        try XCTSkipIf(store.credential(for: first.frameId) == nil, "No keychain available to this test process")
        XCTAssertEqual(store.credential(for: first.frameId), first)
        XCTAssertNil(store.credential(for: second.frameId))
        let replaced = FrameCredential(token: second.token, fp: first.fp)
        store.save(replaced)
        XCTAssertEqual(store.credential(for: first.frameId), replaced)
        XCTAssertFalse(store.removeLegacy())
        XCTAssertEqual(store.credential(for: first.frameId), replaced)
        store.remove(for: first.frameId)
        XCTAssertNil(store.credential(for: first.frameId))
    }

    func testKeychainItemStaysOnThisDevice() throws {
        let service = "com.iframed.you.tests.\(UUID().uuidString)"
        let store = KeychainTokenStore(service: service)
        store.save(first)
        defer { store.remove(for: first.frameId) }
        try XCTSkipIf(store.credential(for: first.frameId) == nil, "No keychain available to this test process")
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrSynchronizable as String: kSecAttrSynchronizableAny, kSecReturnAttributes as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var found: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &found), errSecSuccess)
        let attributes = try XCTUnwrap(found as? [String: Any])
        XCTAssertNotEqual(attributes[kSecAttrSynchronizable as String] as? Bool, true)
        if let accessible = attributes[kSecAttrAccessible as String] as? String {
            XCTAssertEqual(accessible, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        }
    }

    func testKeychainPurgeDeletesFirstVersionTokensAndKeepsPinnedOnes() throws {
        let service = "com.iframed.you.tests.\(UUID().uuidString)"
        let store = KeychainTokenStore(service: service)
        func raw(_ account: String) -> [String: Any] {
            [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        }
        func addLegacy(_ account: String, _ data: Data) -> Bool {
            SecItemAdd(raw(account).merging([kSecValueData as String: data]) { _, new in new } as CFDictionary, nil) == errSecSuccess
        }
        func exists(_ account: String) -> Bool {
            SecItemCopyMatching(raw(account) as CFDictionary, nil) == errSecSuccess
        }
        defer { ["demo-frame", second.frameId, first.frameId].forEach { SecItemDelete(raw($0) as CFDictionary) } }
        try XCTSkipIf(!addLegacy("demo-frame", Data(String(repeating: "c", count: 64).utf8)), "No keychain available to this test process")
        let misfiled = try JSONEncoder().encode(first)
        XCTAssertTrue(addLegacy(second.frameId, misfiled))
        store.save(first)
        XCTAssertNil(store.credential(for: "demo-frame"))
        XCTAssertNil(store.credential(for: second.frameId))
        XCTAssertTrue(store.removeLegacy())
        XCTAssertFalse(exists("demo-frame"))
        XCTAssertFalse(exists(second.frameId))
        XCTAssertEqual(store.credential(for: first.frameId), first)
        XCTAssertFalse(store.removeLegacy())
    }

    func testPairedFrameStorePersistsIdentityButNoAddressOrSecret() throws {
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

    func testDeviceNameStoreFallsBackWhenNothingValidIsSaved() {
        let defaults = isolatedDefaults()
        let names = DeviceNameStore(defaults: defaults, fallback: "iPhone")
        XCTAssertEqual(names.name, "iPhone")
        names.name = "Maya's iPhone"
        XCTAssertEqual(DeviceNameStore(defaults: defaults).name, "Maya's iPhone")
        defaults.set(String(repeating: "n", count: 90), forKey: "skylit.deviceName")
        XCTAssertEqual(names.name, "iPhone")
        XCTAssertEqual(DeviceNameStore(defaults: isolatedDefaults(), fallback: "").name, "")
    }
}
