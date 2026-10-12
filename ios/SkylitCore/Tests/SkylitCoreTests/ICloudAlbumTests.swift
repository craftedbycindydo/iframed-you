import XCTest
@testable import SkylitCore

final class ICloudAlbumModelTests: XCTestCase {
    private func settings(_ json: String) throws -> FrameSettings {
        try JSONDecoder().decode(FrameState.self, from: Data(json.utf8)).settings
    }

    func testAbsentFieldMeansAnOlderFrame() throws {
        let decoded = try settings(##"{"rev":1,"settings":{"location":null,"appearance":{"palette":"linen","mode":"auto"}}}"##)
        XCTAssertFalse(decoded.supportsICloudAlbum)
        XCTAssertNil(decoded.icloudAlbum)
        XCTAssertFalse(try settings(##"{"rev":1}"##).supportsICloudAlbum)
    }

    func testNullMeansSupportedButNotConnected() throws {
        let decoded = try settings(##"{"rev":1,"settings":{"icloudAlbum":null}}"##)
        XCTAssertTrue(decoded.supportsICloudAlbum)
        XCTAssertNil(decoded.icloudAlbum)
    }

    func testSyncingBeforeFirstSync() throws {
        let decoded = try settings(##"{"rev":1,"settings":{"icloudAlbum":{"name":"Family","count":0,"lastSync":null,"syncing":true,"error":null}}}"##)
        XCTAssertEqual(decoded.icloudAlbum, ICloudAlbum(name: "Family", count: 0, lastSync: nil, syncing: true, error: nil))
        XCTAssertNil(decoded.icloudAlbum?.lastSyncDate)
    }

    func testSynced() throws {
        let decoded = try settings(##"{"rev":1,"settings":{"icloudAlbum":{"name":"Family","count":24,"lastSync":"2026-10-11T18:00:00Z","syncing":false,"error":null,"extra":1}}}"##)
        XCTAssertEqual(decoded.icloudAlbum?.count, 24)
        XCTAssertEqual(decoded.icloudAlbum?.syncing, false)
        XCTAssertEqual(decoded.icloudAlbum?.lastSyncDate, fixedDate("2026-10-11T18:00:00Z"))
        XCTAssertNil(decoded.icloudAlbum?.error)
    }

    func testErrorAndSparseObject() throws {
        let failed = try settings(##"{"rev":1,"settings":{"icloudAlbum":{"name":"Family","count":24,"lastSync":"2026-10-11T18:00:00Z","syncing":false,"error":"The album is no longer public"}}}"##)
        XCTAssertEqual(failed.icloudAlbum?.error, "The album is no longer public")
        let sparse = try settings(##"{"rev":1,"settings":{"icloudAlbum":{"error":""}}}"##)
        XCTAssertEqual(sparse.icloudAlbum, ICloudAlbum(name: ""))
    }

    func testEncodingKeepsSupportDistinction() throws {
        for original in [FrameSettings(supportsICloudAlbum: false), FrameSettings(), FrameSettings(icloudAlbum: ICloudAlbum(name: "Family", count: 3, syncing: true))] {
            let decoded = try JSONDecoder().decode(FrameSettings.self, from: JSONEncoder().encode(original))
            XCTAssertEqual(decoded, original)
        }
    }

    func testLinkValidation() {
        XCTAssertEqual(ICloudLink.normalized("https://www.icloud.com/sharedalbum/#B0zEXAMPLEtoken"), "https://www.icloud.com/sharedalbum/#B0zEXAMPLEtoken")
        XCTAssertEqual(ICloudLink.normalized("  https://www.icloud.com/sharedalbum/#B0zEXAMPLEtoken \n"), "https://www.icloud.com/sharedalbum/#B0zEXAMPLEtoken")
        XCTAssertEqual(ICloudLink.normalized("https://www.icloud.com/sharedalbum/en-gb/#B0zEXAMPLEtoken"), "https://www.icloud.com/sharedalbum/en-gb/#B0zEXAMPLEtoken")
        XCTAssertEqual(ICloudLink.normalized("https://share.icloud.com/photos/0a1B2c3D4e5F-6g7H_8i"), "https://share.icloud.com/photos/0a1B2c3D4e5F-6g7H_8i")
        XCTAssertEqual(ICloudLink.normalized("\tB0zEXAMPLEtoken "), "https://www.icloud.com/sharedalbum/#B0zEXAMPLEtoken")
        for rejected in ["", "   ", "short", "http://www.icloud.com/sharedalbum/#B0zEXAMPLEtoken", "https://www.icloud.com/sharedalbum/",
                         "https://www.icloud.com/sharedalbum/#", "https://www.icloud.com.evil.example/sharedalbum/#B0zEXAMPLEtoken",
                         "https://evil.example/?https://www.icloud.com/sharedalbum/#B0zEXAMPLEtoken", "https://share.icloud.com/photos/",
                         "https://www.icloud.com/photos/#B0zEXAMPLEtoken", "https://www.icloud.com/sharedalbum/#B0z5 qAGN1JIFd3y",
                         "two words here", "https://photos.app.goo.gl/x"] {
            XCTAssertNil(ICloudLink.normalized(rejected), rejected)
        }
    }

    func testRequestBuilding() async throws {
        let transport = ScriptedTransport([.status(200, ##"{"rev":4}"##), .status(200, ##"{"rev":5}"##), .status(204, "")])
        let api = makeAPI(transport)
        let connected = try await api.connectICloudAlbum(url: "https://www.icloud.com/sharedalbum/#B0zEXAMPLEtoken")
        XCTAssertEqual(connected.rev, 4)
        let disconnected = try await api.disconnectICloudAlbum()
        XCTAssertEqual(disconnected.rev, 5)
        try await api.syncICloudAlbum()
        let calls = transport.calls
        XCTAssertEqual(calls.map { $0.request.httpMethod }, ["PUT", "DELETE", "POST"])
        XCTAssertEqual(calls.map { $0.request.url?.path }, ["/v1/settings/icloud-album", "/v1/settings/icloud-album", "/v1/settings/icloud-album/sync"])
        XCTAssertEqual(calls[0].json, ["url": "https://www.icloud.com/sharedalbum/#B0zEXAMPLEtoken"])
        XCTAssertNil(calls[1].body)
        XCTAssertNil(calls[2].body)
        XCTAssertTrue(calls.allSatisfy { $0.request.value(forHTTPHeaderField: "Authorization") == "Bearer tok" })
        XCTAssertTrue(calls.allSatisfy { $0.request.url?.query == nil })
    }
}

@MainActor
final class ICloudAlbumStoreTests: XCTestCase {
    private var server: DemoFrameServer!

    override func setUp() async throws {
        server = DemoFrameServer.sample()
    }

    private func loaded() async -> FrameStore {
        let store = FrameStore(frame: PairedFrame(frameId: "demo-frame", name: "Kitchen frame"),
                               api: FrameAPI(baseURL: DemoFrameServer.address, token: DemoFrameServer.demoToken, transport: server))
        await store.refresh()
        return store
    }

    func testConnectSendsCanonicalLinkAndShowsSyncing() async {
        let store = await loaded()
        XCTAssertEqual(store.state?.settings.supportsICloudAlbum, true)
        XCTAssertNil(store.state?.settings.icloudAlbum)
        let connected = await store.connectICloudAlbum(link: "  B0zEXAMPLEtoken\n")
        XCTAssertTrue(connected)
        let put = server.requests.first { $0.method == "PUT" }
        XCTAssertEqual(try? JSONSerialization.jsonObject(with: put?.body ?? Data()) as? NSDictionary, ["url": "https://www.icloud.com/sharedalbum/#B0zEXAMPLEtoken"])
        XCTAssertEqual(store.state?.settings.icloudAlbum?.syncing, true)
        XCTAssertTrue(store.isAlbumSyncing)
        XCTAssertEqual(store.state?.rev, server.revision)
        XCTAssertNil(store.notice)
    }

    func testLocallyInvalidLinkNeverReachesTheFrame() async {
        let store = await loaded()
        let before = server.requests.count
        let connected = await store.connectICloudAlbum(link: "https://example.com/album")
        XCTAssertFalse(connected)
        XCTAssertEqual(server.requests.count, before)
        XCTAssertEqual(store.notice, "That isn't an iCloud shared album link. Copy it from the album's Share Link.")
    }

    func testFrameRejectionShowsItsMessage() async {
        let transport = ScriptedTransport([
            .status(200, ##"{"rev":1,"settings":{"icloudAlbum":null}}"##),
            .status(400, ##"{"error":{"code":"bad_request","message":"That album is not public. Turn on Public Website first."}}"##),
        ])
        let store = FrameStore(frame: PairedFrame(frameId: "f", name: "Kitchen"), api: makeAPI(transport))
        await store.refresh()
        let connected = await store.connectICloudAlbum(link: "https://share.icloud.com/photos/0a1B2c3D4e5F")
        XCTAssertFalse(connected)
        XCTAssertEqual(store.notice, "The frame couldn't use that album. Turn on Public Website for it in Photos, then copy the link again.")
        XCTAssertNil(store.state?.settings.icloudAlbum)
        XCTAssertEqual(transport.calls.count, 2)
    }

    func testSyncTriggerAndSettling() async {
        server.setICloudAlbum(name: "Family", count: 24, lastSync: "2026-10-11T18:00:00Z", syncing: false, error: nil)
        let store = await loaded()
        XCTAssertFalse(store.isAlbumSyncing)
        await store.syncICloudAlbum()
        XCTAssertEqual(server.requests.filter { $0.method == "POST" }.map(\.path), ["/v1/settings/icloud-album/sync"])
        XCTAssertTrue(store.isAlbumSyncing)
        server.setICloudAlbum(name: "Family", count: 26, lastSync: "2026-10-11T19:00:00Z", syncing: false, error: nil)
        await store.poll()
        XCTAssertFalse(store.isAlbumSyncing)
        XCTAssertEqual(store.state?.settings.icloudAlbum?.count, 26)
    }

    func testSyncErrorIsCarriedInState() async {
        server.setICloudAlbum(name: "Family", count: 24, lastSync: "2026-10-11T18:00:00Z", syncing: false, error: "The album is no longer public")
        let store = await loaded()
        XCTAssertEqual(store.state?.settings.icloudAlbum?.error, "The album is no longer public")
    }

    func testSyncWithoutAnAlbumExplains() async {
        let store = await loaded()
        await store.syncICloudAlbum()
        XCTAssertEqual(store.notice, "The frame can't do that right now.")
        XCTAssertFalse(store.isAlbumSyncing)
    }

    func testDisconnect() async {
        server.setICloudAlbum(name: "Family", count: 24, lastSync: nil, syncing: false, error: nil)
        let store = await loaded()
        let disconnected = await store.disconnectICloudAlbum()
        XCTAssertTrue(disconnected)
        XCTAssertNil(store.state?.settings.icloudAlbum)
        XCTAssertEqual(store.state?.settings.supportsICloudAlbum, true)
        XCTAssertEqual(server.requests.last?.method, "DELETE")
        XCTAssertEqual(store.state?.rev, server.revision)
        await store.refresh()
        XCTAssertNil(store.state?.settings.icloudAlbum)
    }

    func testOlderFrameIsReportedAsUnsupported() async {
        server.removeICloudSupport()
        let store = await loaded()
        XCTAssertEqual(store.state?.settings.supportsICloudAlbum, false)
        let connected = await store.connectICloudAlbum(link: "B0zEXAMPLEtoken")
        XCTAssertFalse(connected)
        XCTAssertEqual(store.notice, "That no longer exists on the frame.")
    }

    func testPollingSpeedsUpOnlyWhileSyncing() async {
        server.setICloudAlbum(name: "Family", count: 24, lastSync: nil, syncing: true, error: nil)
        let store = await loaded()
        let start = server.requests.count
        let task = Task { await store.runPolling(every: .seconds(30), whileSyncing: .milliseconds(10)) }
        for _ in 0..<2000 where server.requests.count < start + 3 {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertGreaterThanOrEqual(server.requests.count, start + 3)
        server.setICloudAlbum(name: "Family", count: 25, lastSync: "2026-10-11T19:00:00Z", syncing: false, error: nil)
        for _ in 0..<2000 where store.isAlbumSyncing {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertFalse(store.isAlbumSyncing)
        let settled = server.requests.count
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(server.requests.count, settled)
        task.cancel()
        await task.value
    }
}
