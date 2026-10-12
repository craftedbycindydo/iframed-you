import XCTest
@testable import SkylitCore

final class DiscoveryTests: XCTestCase {
    func testResultsAreDeduplicatedAndSorted() {
        let frames = DiscoveredFrame.unique([
            DiscoveredFrame(frameId: "b", name: "living room"),
            DiscoveredFrame(frameId: "a", name: "Kitchen"),
            DiscoveredFrame(frameId: "b", name: "living room (2)"),
        ])
        XCTAssertEqual(frames.map(\.frameId), ["a", "b"])
        XCTAssertEqual(frames[1].name, "living room")
    }

    func testManualAddressParsingIsHTTPSOnly() {
        XCTAssertEqual(FrameAddress.parse("192.168.1.20:8765")?.absoluteString, "https://192.168.1.20:8765")
        XCTAssertEqual(FrameAddress.parse(" 192.168.1.20 ")?.absoluteString, "https://192.168.1.20:8765")
        XCTAssertEqual(FrameAddress.parse("frame.local:9000")?.absoluteString, "https://frame.local:9000")
        XCTAssertEqual(FrameAddress.parse("https://192.168.1.20:8765/v2/info")?.absoluteString, "https://192.168.1.20:8765")
        XCTAssertNil(FrameAddress.parse(""))
        XCTAssertNil(FrameAddress.parse("http://192.168.1.20"))
        XCTAssertNil(FrameAddress.parse("http://192.168.1.20:8765"))
        XCTAssertNil(FrameAddress.parse("ftp://192.168.1.20"))
        XCTAssertNil(FrameAddress.parse("user:pw@192.168.1.20"))
        XCTAssertNil(FrameAddress.parse("192.168.1.20:99999"))
        XCTAssertNil(FrameAddress.parse("two words"))
    }

    func testResolvedHostDropsInterfaceScope() {
        XCTAssertEqual(FrameAddress.url(host: "192.168.1.20%en0", port: 8765)?.absoluteString, "https://192.168.1.20:8765")
    }
}

@MainActor
final class FrameSessionTests: XCTestCase {
    private var server: DemoFrameServer!
    private var impostor: DemoFrameServer!
    private var network: DemoNetwork!
    private var browser: StaticFrameBrowser!
    private var tokens: InMemoryTokenStore!
    private var defaults: UserDefaults!

    private var kitchen: DiscoveredFrame { DiscoveredFrame(frameId: server.frameId, name: "Kitchen frame") }
    private var savedFrame: PairedFrame { PairedFrame(frameId: server.frameId, name: "Kitchen frame", address: DemoFrameServer.address) }
    private let evil = URL(string: "https://evil.local:8765")!

    override func setUp() async throws {
        server = DemoFrameServer.sample()
        impostor = DemoFrameServer(identity: "impostor", name: "Kitchen frame")
        impostor.claimFrameId(server.frameId)
        impostor.openPairingWindow()
        network = DemoNetwork(server)
        network.place(impostor, at: "evil.local")
        browser = StaticFrameBrowser(addresses: ["Skylit": DemoFrameServer.address, "Evil": evil])
        tokens = InMemoryTokenStore()
        defaults = isolatedDefaults()
    }

    private func makeSession(_ store: TokenStoring? = nil) -> FrameSession {
        FrameSession(browser: browser, connector: network, tokens: store ?? tokens, pairedStore: PairedFrameStore(defaults: defaults),
                     deviceNames: DeviceNameStore(defaults: defaults, fallback: "Test phone"), pollInterval: .milliseconds(1))
    }

    private func rememberPairing() {
        tokens.save(server.credential)
        PairedFrameStore(defaults: defaults).current = PairedFrame(frameId: server.frameId, name: "Kitchen frame")
    }

    private func assertNothingSecretReached(_ target: DemoFrameServer, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(target.requests.allSatisfy { $0.path == "/v2/info" && $0.headers["Authorization"] == nil && $0.body == nil }, file: file, line: line)
    }

    func testFreshInstallListsFramesWithoutConnecting() async {
        let session = makeSession()
        XCTAssertEqual(session.discovery, .searching)
        await session.receive(.services(["Skylit"]))
        XCTAssertEqual(session.frames, [kitchen])
        XCTAssertNil(session.store)
        XCTAssertNil(session.paired)
        XCTAssertNil(session.warning)
        XCTAssertFalse(session.hasToken(for: kitchen))
        XCTAssertEqual(server.requests.map(\.path), ["/v2/info"])
        XCTAssertEqual(server.requests[0].url.scheme, "https")
        assertNothingSecretReached(server)
    }

    func testPermissionDeniedAndBrowseFailure() async {
        let session = makeSession()
        await session.receive(.permissionDenied)
        XCTAssertEqual(session.discovery, .permissionDenied)
        await session.receive(.failed("Network is down"))
        XCTAssertEqual(session.discovery, .failed("Network is down"))
        await session.receive(.services([]))
        XCTAssertEqual(session.discovery, .searching)
        XCTAssertTrue(session.frames.isEmpty)
    }

    func testPairingEndToEnd() async throws {
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        await session.select(kitchen)
        XCTAssertEqual(session.pairing?.step, .naming)
        XCTAssertEqual(session.pairing?.frameName, "Kitchen frame")
        XCTAssertEqual(session.pairing?.suggestedName, "Test phone")
        assertNothingSecretReached(server)

        await session.startPairing(name: "Maya's iPhone")
        XCTAssertEqual(session.pairing?.step, .naming)
        XCTAssertEqual(session.pairing?.message, PairingFlow.windowText)
        assertNothingSecretReached(server)

        server.openPairingWindow()
        await session.startPairing(name: "Maya's iPhone")
        XCTAssertEqual(session.pairing?.step, .enteringCode)
        let code = try XCTUnwrap(server.shownCode)
        await session.submit(code: code == "000000" ? "111111" : "000000")
        XCTAssertNil(session.store)
        XCTAssertEqual(session.pairing?.message, "That code didn't match. 2 tries left.")
        XCTAssertNil(tokens.credential(for: server.frameId))

        await session.submit(code: code)
        XCTAssertNil(session.pairing)
        XCTAssertEqual(session.paired, savedFrame)
        XCTAssertEqual(session.store?.link, .online)
        XCTAssertEqual(session.store?.state?.rev, 42)
        let credential = try XCTUnwrap(tokens.credential(for: server.frameId))
        XCTAssertEqual(credential.fp, server.fingerprint)
        XCTAssertTrue(Hex.isValid(credential.token, bytes: 32))
        XCTAssertEqual(PairedFrameStore(defaults: defaults).current, savedFrame)
        XCTAssertEqual(server.requests.last?.headers["Authorization"], "Bearer \(credential.token)")
        XCTAssertEqual(DeviceNameStore(defaults: defaults).name, "Maya's iPhone")
        await session.store?.loadDevices()
        XCTAssertEqual(session.store?.thisDevice?.name, "Maya's iPhone")
    }

    func testPairingThatCannotBeSavedSaysSo() async throws {
        final class ForgetfulStore: TokenStoring {
            func credential(for frameId: String) -> FrameCredential? { nil }
            func save(_ credential: FrameCredential) {}
            func remove(for frameId: String) {}
            func removeLegacy() -> Bool { false }
        }
        server.openPairingWindow()
        let session = makeSession(ForgetfulStore())
        await session.receive(.services(["Skylit"]))
        await session.select(kitchen)
        await session.startPairing(name: "Test phone")
        await session.submit(code: try XCTUnwrap(server.shownCode))
        XCTAssertEqual(session.store?.link, .online)
        XCTAssertEqual(session.notice, "Paired, but this phone couldn't save the pairing. You'll need to pair again next time.")
    }

    func testCancelPairingTellsTheFrame() async throws {
        server.openPairingWindow()
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        await session.select(kitchen)
        await session.startPairing(name: "Test phone")
        let code = try XCTUnwrap(server.shownCode)
        await session.cancelPairing()
        XCTAssertNil(session.pairing)
        XCTAssertEqual(server.requests.last?.path, "/v2/pair/cancel")
        await session.submit(code: code)
        XCTAssertNil(session.store)
        XCTAssertNil(tokens.credential(for: server.frameId))
    }

    func testRelaunchReconnectsByFrameIdOnceBonjourFindsIt() async {
        rememberPairing()
        let session = makeSession()
        XCTAssertEqual(session.paired?.frameId, server.frameId)
        XCTAssertNil(session.store)
        await session.receive(.services(["Printer"]))
        XCTAssertNil(session.store)
        await session.receive(.services(["Skylit"]))
        XCTAssertEqual(session.store?.state?.rev, 42)
        XCTAssertNil(session.pairing)
        XCTAssertNil(session.warning)
    }

    func testSavedFrameWithoutTokenIsNotTreatedAsPaired() {
        PairedFrameStore(defaults: defaults).current = savedFrame
        XCTAssertNil(makeSession().paired)
        XCTAssertNil(PairedFrameStore(defaults: defaults).current)
    }

    func testLaunchDeletesFirstVersionTokensAndAsksToPairAgain() async {
        tokens = InMemoryTokenStore(legacy: ["demo-frame": "first-version-token"])
        PairedFrameStore(defaults: defaults).current = PairedFrame(frameId: "demo-frame", name: "Kitchen frame")
        let session = makeSession()
        XCTAssertTrue(tokens.legacyTokens.isEmpty)
        XCTAssertNil(session.paired)
        XCTAssertNil(PairedFrameStore(defaults: defaults).current)
        XCTAssertEqual(session.warning, "The frame was updated. Pair again for a secure connection.")
        await session.receive(.services(["Skylit"]))
        XCTAssertNil(session.store)
        assertNothingSecretReached(server)
        XCTAssertNil(makeSession().warning)
    }

    func testSelectingAFrameWithAStoredTokenSkipsPairing() async {
        tokens.save(server.credential)
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        XCTAssertTrue(session.hasToken(for: kitchen))
        await session.select(kitchen)
        XCTAssertNil(session.pairing)
        XCTAssertEqual(session.store?.link, .online)
    }

    func testFrameThatLeavesBeforePairingStartsIsExplained() async {
        let session = makeSession()
        await session.select(kitchen)
        XCTAssertNil(session.pairing)
        XCTAssertEqual(session.notice, "Couldn't reach Kitchen frame. Make sure it is on and on the same Wi-Fi.")
        XCTAssertFalse(session.isBusy)
        await session.receive(.services(["Skylit"]))
        server.setUnreachable(true)
        await session.select(kitchen)
        await session.startPairing(name: "Test phone")
        XCTAssertEqual(session.pairing?.step, .naming)
        XCTAssertEqual(session.pairing?.message, FrameError.offline.userMessage)
    }

    func testRemovalOnTheFrameIsTheOnlyThingThatDeletesTheCredential() async {
        rememberPairing()
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        let store = session.store
        XCTAssertNotNil(store)
        server.setUnreachable(true)
        await store?.poll()
        XCTAssertNotNil(tokens.credential(for: server.frameId))
        server.setUnreachable(false)
        server.revokeAll()
        await store?.poll()
        XCTAssertNil(session.store)
        XCTAssertNil(session.paired)
        XCTAssertNil(tokens.credential(for: server.frameId))
        XCTAssertNil(PairedFrameStore(defaults: defaults).current)
        XCTAssertEqual(session.notice, "This phone was removed from Kitchen frame. Pair again to continue.")
        await session.select(kitchen)
        XCTAssertEqual(session.pairing?.step, .naming)
    }

    func testStaleTokenOnLaunchReturnsToPairing() async {
        tokens.save(FrameCredential(token: String(repeating: "0", count: 64), fp: server.fingerprint))
        PairedFrameStore(defaults: defaults).current = savedFrame
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        XCTAssertNil(session.store)
        XCTAssertNil(session.paired)
        XCTAssertNil(tokens.credential(for: server.frameId))
    }

    func testFrameRebootWithNewAddressIsFollowedViaBonjour() async {
        rememberPairing()
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        server.setUnreachable(true)
        await session.store?.poll()
        XCTAssertEqual(session.store?.link, .offline)
        await session.receive(.services([]))
        XCTAssertEqual(session.store?.link, .offline)
        server.setUnreachable(false)
        network.place(nil, at: "demo-frame.local")
        network.place(server, at: "192.168.1.99")
        browser.move("Skylit", to: nil)
        browser.move("Skylit (2)", to: URL(string: "https://192.168.1.99:41234"))
        await session.receive(.services(["Skylit (2)"]))
        XCTAssertEqual(session.store?.link, .online)
        XCTAssertEqual(server.requests.last?.url.host, "192.168.1.99")
        XCTAssertEqual(server.requests.last?.url.port, 41234)
    }

    func testEveryAdvertIsTriedAndOnlyThePinnedOneIsUsed() async {
        rememberPairing()
        let session = makeSession()
        await session.receive(.services(["Evil", "Skylit"]))
        XCTAssertEqual(session.store?.link, .online)
        XCTAssertEqual(session.store?.state?.rev, 42)
        XCTAssertEqual(impostor.requests.count, 1)
        assertNothingSecretReached(impostor)
        XCTAssertEqual(session.warning, "Another device on this Wi-Fi is claiming to be Kitchen frame. Nothing was sent.")
        XCTAssertEqual(session.store?.notice, session.warning)
        XCTAssertEqual(tokens.credential(for: server.frameId), server.credential)
        XCTAssertTrue(server.requests.filter { $0.headers["Authorization"] != nil }.allSatisfy { $0.url.host == "demo-frame.local" })
    }

    func testImpostorAloneGetsNothingAndNothingIsDeleted() async {
        rememberPairing()
        let session = makeSession()
        await session.receive(.services(["Evil"]))
        XCTAssertNil(session.store)
        XCTAssertEqual(session.paired?.frameId, server.frameId)
        XCTAssertEqual(tokens.credential(for: server.frameId), server.credential)
        XCTAssertEqual(PairedFrameStore(defaults: defaults).current?.frameId, server.frameId)
        XCTAssertEqual(session.warning, "Another device on this Wi-Fi is claiming to be Kitchen frame. Nothing was sent.")
        XCTAssertTrue(session.frames.isEmpty)
        XCTAssertEqual(impostor.requests.count, 1)
        assertNothingSecretReached(impostor)
        XCTAssertTrue(server.requests.isEmpty)

        await session.connect(manualAddress: "evil.local")
        XCTAssertNil(session.store)
        XCTAssertNil(session.pairing)
        XCTAssertEqual(tokens.credential(for: server.frameId), server.credential)
        assertNothingSecretReached(impostor)

        await session.receive(.services(["Evil", "Skylit"]))
        XCTAssertEqual(session.store?.link, .online)
    }

    func testImpostorAnswering401CannotUnpairThePhone() async {
        rememberPairing()
        impostor.revokeAll()
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        network.place(impostor, at: "demo-frame.local")
        await session.store?.poll()
        XCTAssertEqual(session.store?.link, .offline)
        XCTAssertEqual(session.paired, savedFrame)
        XCTAssertEqual(tokens.credential(for: server.frameId), server.credential)
        XCTAssertTrue(impostor.requests.isEmpty)
    }

    func testAnUnpairedPhoneDoesNotListAFrameWhoseIdIsNotItsCertificate() async {
        let session = makeSession()
        await session.receive(.services(["Evil"]))
        XCTAssertTrue(session.frames.isEmpty)
        await session.connect(manualAddress: "evil.local")
        XCTAssertNil(session.pairing)
        XCTAssertEqual(session.notice, "No frame answered at that address. Check it and try again.")
    }

    func testIdentityComesFromInfoNotFromTheServiceName() async {
        browser.move("Somebody else's label", to: DemoFrameServer.address)
        browser.move("Dead", to: nil)
        let session = makeSession()
        await session.receive(.services(["Dead", "Skylit", "Somebody else's label"]))
        XCTAssertEqual(session.frames, [kitchen])
    }

    func testServiceThatDoesNotAnswerInfoIsNotListed() async {
        server.setUnreachable(true)
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        XCTAssertTrue(session.frames.isEmpty)
    }

    func testManualAddressFallback() async throws {
        network.place(nil, at: "demo-frame.local")
        network.place(server, at: "10.0.0.5")
        server.openPairingWindow()
        let session = makeSession()
        await session.connect(manualAddress: "not an address")
        XCTAssertEqual(session.notice, "Enter the frame's address, for example 192.168.1.20:8765.")
        XCTAssertTrue(server.requests.isEmpty)
        session.notice = nil
        await session.connect(manualAddress: "10.0.0.5:8765")
        XCTAssertEqual(server.requests.first?.path, "/v2/info")
        XCTAssertEqual(server.requests.first?.url.scheme, "https")
        assertNothingSecretReached(server)
        XCTAssertEqual(session.pairing?.step, .naming)
        await session.startPairing(name: "Test phone")
        await session.submit(code: try XCTUnwrap(server.shownCode))
        XCTAssertEqual(session.store?.link, .online)
        XCTAssertEqual(server.requests.last?.url.host, "10.0.0.5")
        XCTAssertNil(defaults.dictionaryRepresentation().values.first { "\($0)".contains("10.0.0.5") })
    }

    func testFramePairedByAddressIsFoundAgainAfterRelaunchWithoutBonjour() async {
        let first = makeSession()
        await first.receive(.permissionDenied)
        tokens.save(server.credential)
        await first.connect(manualAddress: "demo-frame.local:8765")
        XCTAssertNotNil(first.store)
        XCTAssertEqual(PairedFrameStore(defaults: defaults).current?.address, DemoFrameServer.address)

        let relaunched = makeSession()
        await relaunched.receive(.permissionDenied)
        XCTAssertNil(relaunched.store)
        XCTAssertNotNil(relaunched.paired)
        await relaunched.reconnect()
        XCTAssertNotNil(relaunched.store)
        XCTAssertEqual(relaunched.store?.state?.rev, server.revision)
    }

    func testStoredAddressIsOnlyTriedWhenNoAdvertisedServiceMatches() async {
        rememberPairing()
        PairedFrameStore(defaults: defaults).current = PairedFrame(frameId: server.frameId, name: "Kitchen frame", address: evil)
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        XCTAssertNotNil(session.store)
        XCTAssertNil(session.warning)
        assertNothingSecretReached(impostor)
    }

    func testManualAddressWithNoFrameBehindIt() async {
        server.setUnreachable(true)
        let session = makeSession()
        await session.connect(manualAddress: "10.0.0.5")
        XCTAssertNil(session.pairing)
        XCTAssertEqual(session.notice, "No frame answered at that address. Check it and try again.")
        XCTAssertFalse(session.isBusy)
    }

    func testForgetRemovesTokenAndLeaveKeepsIt() async {
        tokens.save(server.credential)
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        await session.select(kitchen)
        session.leave()
        XCTAssertNil(session.store)
        XCTAssertNil(session.paired)
        XCTAssertNotNil(tokens.credential(for: server.frameId))
        await session.select(kitchen)
        session.forget()
        XCTAssertNil(session.store)
        XCTAssertNil(tokens.credential(for: server.frameId))
        XCTAssertNil(PairedFrameStore(defaults: defaults).current)
    }

    func testUnpairRemovesThisPhoneOnTheFrameThenForgets() async {
        rememberPairing()
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        await session.unpair()
        XCTAssertEqual(server.requests.last?.method, "DELETE")
        XCTAssertEqual(server.requests.last?.path, "/v1/devices/d1")
        XCTAssertNil(session.store)
        XCTAssertNil(session.paired)
        XCTAssertNil(session.notice)
        XCTAssertNil(tokens.credential(for: server.frameId))
        let stranger = FrameAPI(baseURL: DemoFrameServer.address, token: DemoFrameServer.demoToken, transport: server)
        do {
            _ = try await stranger.state()
            XCTFail("the removed phone's token must stop working")
        } catch {
            XCTAssertEqual(error as? FrameError, .unauthorized)
        }
    }

    func testUnpairWhileTheFrameIsUnreachableForgetsAndSaysWhatToDoOnTheFrame() async {
        rememberPairing()
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        XCTAssertNotNil(session.store)
        server.setUnreachable(true)
        await session.unpair()
        XCTAssertNil(session.store)
        XCTAssertNil(session.paired)
        XCTAssertNil(tokens.credential(for: server.frameId))
        XCTAssertEqual(session.notice, FrameSession.unpairOfflineText("Kitchen frame"))
        XCTAssertTrue(session.notice?.contains("Phone app") ?? false)
    }

    func testRunConsumesBrowserEvents() async {
        rememberPairing()
        browser = StaticFrameBrowser(events: [.services(["Skylit"])], addresses: ["Skylit": DemoFrameServer.address])
        let session = makeSession()
        let task = Task { await session.run() }
        for _ in 0..<2000 where session.store?.state == nil {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(session.store?.state?.rev, 42)
        browser.send(.permissionDenied)
        for _ in 0..<2000 where session.discovery != .permissionDenied {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(session.discovery, .permissionDenied)
        browser.finish()
        await task.value
    }
}
