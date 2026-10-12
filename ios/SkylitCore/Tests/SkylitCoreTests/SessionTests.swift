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

    func testManualAddressParsing() {
        XCTAssertEqual(FrameAddress.parse("192.168.1.20:8765")?.absoluteString, "http://192.168.1.20:8765")
        XCTAssertEqual(FrameAddress.parse(" 192.168.1.20 ")?.absoluteString, "http://192.168.1.20:8765")
        XCTAssertEqual(FrameAddress.parse("frame.local:9000")?.absoluteString, "http://frame.local:9000")
        XCTAssertEqual(FrameAddress.parse("http://192.168.1.20:8765/v1/info")?.absoluteString, "http://192.168.1.20:8765")
        XCTAssertNil(FrameAddress.parse(""))
        XCTAssertNil(FrameAddress.parse("https://192.168.1.20"))
        XCTAssertNil(FrameAddress.parse("ftp://192.168.1.20"))
        XCTAssertNil(FrameAddress.parse("user:pw@192.168.1.20"))
        XCTAssertNil(FrameAddress.parse("192.168.1.20:99999"))
        XCTAssertNil(FrameAddress.parse("two words"))
    }

    func testResolvedHostDropsInterfaceScope() {
        XCTAssertEqual(FrameAddress.url(host: "192.168.1.20%en0", port: 8765)?.absoluteString, "http://192.168.1.20:8765")
    }
}

@MainActor
final class FrameSessionTests: XCTestCase {
    private let kitchen = DiscoveredFrame(frameId: "demo-frame", name: "Kitchen frame")
    private var server: DemoFrameServer!
    private var browser: StaticFrameBrowser!
    private var tokens: InMemoryTokenStore!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        server = DemoFrameServer.sample()
        browser = StaticFrameBrowser(addresses: ["Skylit": DemoFrameServer.address])
        tokens = InMemoryTokenStore()
        defaults = isolatedDefaults()
    }

    private func makeSession() -> FrameSession {
        FrameSession(browser: browser, transport: server, tokens: tokens,
                     pairedStore: PairedFrameStore(defaults: defaults), deviceName: "Test phone")
    }

    func testFreshInstallListsFramesWithoutConnecting() async {
        let session = makeSession()
        XCTAssertEqual(session.discovery, .searching)
        await session.receive(.services(["Skylit"]))
        XCTAssertEqual(session.frames, [kitchen])
        XCTAssertNil(session.store)
        XCTAssertNil(session.paired)
        XCTAssertFalse(session.hasToken(for: kitchen))
        XCTAssertEqual(server.requests.map(\.path), ["/v1/info"])
        XCTAssertNil(server.requests[0].headers["Authorization"])
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

    func testPairingEndToEnd() async {
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        await session.select(kitchen)
        XCTAssertEqual(session.pairing?.step, .awaitingCode)
        XCTAssertEqual(session.pairing?.frameName, "Kitchen frame")
        XCTAssertNil(session.store)
        await session.submit(code: "000000")
        XCTAssertNil(session.store)
        XCTAssertNotNil(session.pairing?.message)
        await session.submit(code: server.pairingCode)
        XCTAssertNil(session.pairing)
        XCTAssertEqual(session.paired, PairedFrame(frameId: "demo-frame", name: "Kitchen frame"))
        XCTAssertEqual(session.store?.link, .online)
        XCTAssertEqual(session.store?.state?.rev, 42)
        XCTAssertEqual(tokens.token(for: "demo-frame")?.count, 64)
        XCTAssertEqual(PairedFrameStore(defaults: defaults).current?.frameId, "demo-frame")
        XCTAssertEqual(server.requests.last?.headers["Authorization"], "Bearer \(tokens.token(for: "demo-frame")!)")
    }

    func testPairingThatCannotBeSavedSaysSo() async {
        final class ForgetfulStore: TokenStoring {
            func token(for frameId: String) -> String? { nil }
            func save(_ token: String, for frameId: String) {}
            func removeToken(for frameId: String) {}
        }
        let session = FrameSession(browser: browser, transport: server, tokens: ForgetfulStore(),
                                   pairedStore: PairedFrameStore(defaults: defaults), deviceName: "Test phone")
        await session.receive(.services(["Skylit"]))
        await session.select(kitchen)
        await session.submit(code: server.pairingCode)
        XCTAssertEqual(session.store?.link, .online)
        XCTAssertEqual(session.notice, "Paired, but this phone couldn't save the pairing. You'll need a new code next time.")
    }

    func testCancelPairing() async {
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        await session.select(kitchen)
        session.cancelPairing()
        XCTAssertNil(session.pairing)
        await session.submit(code: server.pairingCode)
        XCTAssertNil(session.store)
    }

    func testRelaunchReconnectsByFrameIdOnceBonjourFindsIt() async {
        tokens.save(DemoFrameServer.demoToken, for: "demo-frame")
        PairedFrameStore(defaults: defaults).current = PairedFrame(frameId: "demo-frame", name: "Kitchen frame")
        let session = makeSession()
        XCTAssertEqual(session.paired?.frameId, "demo-frame")
        XCTAssertNil(session.store)
        await session.receive(.services(["Printer"]))
        XCTAssertNil(session.store)
        await session.receive(.services(["Skylit"]))
        XCTAssertEqual(session.store?.state?.rev, 42)
        XCTAssertNil(session.pairing)
    }

    func testSavedFrameWithoutTokenIsNotTreatedAsPaired() {
        PairedFrameStore(defaults: defaults).current = PairedFrame(frameId: "demo-frame", name: "Kitchen frame")
        XCTAssertNil(makeSession().paired)
    }

    func testSelectingAFrameWithAStoredTokenSkipsPairing() async {
        tokens.save(DemoFrameServer.demoToken, for: "demo-frame")
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        XCTAssertTrue(session.hasToken(for: kitchen))
        await session.select(kitchen)
        XCTAssertNil(session.pairing)
        XCTAssertEqual(session.store?.link, .online)
    }

    func testFrameThatCannotBeResolvedShowsNotice() async {
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        browser.move("Skylit", to: nil)
        await session.select(kitchen)
        XCTAssertNil(session.pairing)
        XCTAssertEqual(session.notice, "Couldn't reach Kitchen frame. Make sure it is on and on the same Wi-Fi.")
        XCTAssertFalse(session.isBusy)
    }

    func testRevokedTokenReturnsToPairing() async {
        tokens.save(DemoFrameServer.demoToken, for: "demo-frame")
        PairedFrameStore(defaults: defaults).current = PairedFrame(frameId: "demo-frame", name: "Kitchen frame")
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        let store = session.store
        XCTAssertNotNil(store)
        server.revokeAll()
        await store?.poll()
        XCTAssertNil(session.store)
        XCTAssertNil(session.paired)
        XCTAssertNil(tokens.token(for: "demo-frame"))
        XCTAssertNil(PairedFrameStore(defaults: defaults).current)
        XCTAssertEqual(session.notice, "This phone was removed from Kitchen frame. Pair again to continue.")
        await session.select(kitchen)
        XCTAssertEqual(session.pairing?.step, .awaitingCode)
    }

    func testStaleTokenOnLaunchReturnsToPairing() async {
        tokens.save("revoked-elsewhere", for: "demo-frame")
        PairedFrameStore(defaults: defaults).current = PairedFrame(frameId: "demo-frame", name: "Kitchen frame")
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        XCTAssertNil(session.store)
        XCTAssertNil(session.paired)
        XCTAssertNil(tokens.token(for: "demo-frame"))
    }

    func testFrameRebootWithNewAddressIsFollowedViaBonjour() async {
        tokens.save(DemoFrameServer.demoToken, for: "demo-frame")
        PairedFrameStore(defaults: defaults).current = PairedFrame(frameId: "demo-frame", name: "Kitchen frame")
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        server.setUnreachable(true)
        await session.store?.poll()
        XCTAssertEqual(session.store?.link, .offline)
        await session.receive(.services([]))
        XCTAssertEqual(session.store?.link, .offline)
        server.setUnreachable(false)
        browser.move("Skylit", to: nil)
        browser.move("Skylit (2)", to: URL(string: "http://192.168.1.99:41234"))
        await session.receive(.services(["Skylit (2)"]))
        XCTAssertEqual(session.store?.link, .online)
        XCTAssertEqual(server.requests.last?.url.host, "192.168.1.99")
        XCTAssertEqual(server.requests.last?.url.port, 41234)
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

    func testManualAddressFallback() async {
        browser.move("Skylit", to: nil)
        let session = makeSession()
        await session.connect(manualAddress: "not an address")
        XCTAssertEqual(session.notice, "Enter the frame's address, for example 192.168.1.20:8765.")
        XCTAssertTrue(server.requests.isEmpty)
        session.notice = nil
        await session.connect(manualAddress: "10.0.0.5:8765")
        XCTAssertEqual(server.requests.first?.path, "/v1/info")
        XCTAssertNil(server.requests.first?.headers["Authorization"])
        XCTAssertEqual(session.pairing?.step, .awaitingCode)
        await session.submit(code: server.pairingCode)
        XCTAssertEqual(session.store?.link, .online)
        XCTAssertEqual(server.requests.last?.url.host, "10.0.0.5")
        XCTAssertNil(defaults.dictionaryRepresentation().values.first { "\($0)".contains("10.0.0.5") })
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
        tokens.save(DemoFrameServer.demoToken, for: "demo-frame")
        let session = makeSession()
        await session.receive(.services(["Skylit"]))
        await session.select(kitchen)
        session.leave()
        XCTAssertNil(session.store)
        XCTAssertNil(session.paired)
        XCTAssertNotNil(tokens.token(for: "demo-frame"))
        await session.select(kitchen)
        session.forget()
        XCTAssertNil(session.store)
        XCTAssertNil(tokens.token(for: "demo-frame"))
        XCTAssertNil(PairedFrameStore(defaults: defaults).current)
    }

    func testRunConsumesBrowserEvents() async {
        tokens.save(DemoFrameServer.demoToken, for: "demo-frame")
        PairedFrameStore(defaults: defaults).current = PairedFrame(frameId: "demo-frame", name: "Kitchen frame")
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
