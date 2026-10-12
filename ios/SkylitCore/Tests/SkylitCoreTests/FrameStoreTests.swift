import XCTest
@testable import SkylitCore

final class GatedTransport: HTTPTransport, @unchecked Sendable {
    private let inner: HTTPTransport
    private let lock = NSLock()
    private var held: [CheckedContinuation<Void, Never>] = []
    private var isHolding = false

    init(_ inner: HTTPTransport) {
        self.inner = inner
    }

    func hold() {
        lock.withLock { isHolding = true }
    }

    var heldCount: Int { lock.withLock { held.count } }

    func release() {
        let waiting: [CheckedContinuation<Void, Never>] = lock.withLock {
            isHolding = false
            defer { held = [] }
            return held
        }
        waiting.forEach { $0.resume() }
    }

    func send(_ request: URLRequest, body: Data?, onProgress: (@Sendable (Double) -> Void)?) async throws -> (Data, HTTPURLResponse) {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let wait = lock.withLock {
                if isHolding { held.append(continuation) }
                return isHolding
            }
            if !wait { continuation.resume() }
        }
        return try await inner.send(request, body: body, onProgress: onProgress)
    }
}

@MainActor
final class FrameStoreTests: XCTestCase {
    private let sunday = fixedDate("2026-10-11T18:00:00Z")
    private var server: DemoFrameServer!

    override func setUp() async throws {
        server = DemoFrameServer.sample(now: sunday)
    }

    private func makeStore(_ transport: HTTPTransport? = nil, token: String = DemoFrameServer.demoToken) -> FrameStore {
        let api = FrameAPI(baseURL: DemoFrameServer.address, token: token, transport: transport ?? server)
        let date = sunday
        return FrameStore(frame: PairedFrame(frameId: "demo-frame", name: "Kitchen frame"), api: api, now: { date })
    }

    private func loaded(_ transport: HTTPTransport? = nil) async -> FrameStore {
        let store = makeStore(transport)
        await store.refresh()
        return store
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<2000 where !condition() {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    func testRefreshLoadsStateAndGoesOnline() async {
        let store = makeStore()
        XCTAssertEqual(store.link, .connecting)
        XCTAssertNil(store.state)
        await store.refresh()
        XCTAssertEqual(store.link, .online)
        XCTAssertEqual(store.state?.rev, 42)
        XCTAssertEqual(store.state?.people.map(\.name), ["Maya", "Leo", "Sam"])
        XCTAssertEqual(store.state?.settings.location?.name, "Calgary")
        XCTAssertEqual(store.state?.photos.count, 6)
        XCTAssertNil(server.requests[0].query)
    }

    func testPollSendsSinceAndKeepsStateOnNotModified() async {
        let store = await loaded()
        let before = store.state
        await store.poll()
        XCTAssertEqual(server.requests.last?.query, "since=42")
        XCTAssertEqual(store.state, before)
        XCTAssertEqual(store.link, .online)
    }

    func testPollPicksUpChangesMadeOnTheFrame() async {
        let store = await loaded()
        server.changeFromFrame { $0.append(["id": "s99", "name": "Butter", "qty": 1, "note": "", "done": false]) }
        await store.poll()
        XCTAssertEqual(store.state?.rev, 43)
        XCTAssertEqual(store.state?.shopping.last?.name, "Butter")
    }

    func testOptimisticChangeShowsBeforeTheFrameAnswers() async {
        let gate = GatedTransport(server)
        let store = await loaded(gate)
        gate.hold()
        let task = Task { await store.setItem(id: "s1", done: true) }
        await waitUntil { gate.heldCount == 1 }
        XCTAssertEqual(store.state?.shopping.first { $0.id == "s1" }?.done, true)
        XCTAssertEqual(store.state?.rev, 42)
        gate.release()
        let succeeded = await task.value
        XCTAssertTrue(succeeded)
        XCTAssertEqual(store.state?.rev, 43)
        XCTAssertEqual(store.state?.shopping.first { $0.id == "s1" }?.done, true)
    }

    func testTwoQuickChangesBothStickAndEndOnTheFrameRevision() async {
        let gate = GatedTransport(server)
        let store = await loaded(gate)
        gate.hold()
        let first = Task { await store.setItem(id: "s1", done: true) }
        let second = Task { await store.setItem(id: "s2", done: true) }
        await waitUntil { gate.heldCount == 2 }
        XCTAssertEqual(store.state?.shopping.filter(\.done).map(\.id), ["s1", "s2", "s4", "s5"])
        gate.release()
        let outcomes = await (first.value, second.value)
        XCTAssertEqual(outcomes.0, true)
        XCTAssertEqual(outcomes.1, true)
        XCTAssertEqual(store.state?.rev, server.revision)
        XCTAssertEqual(store.state?.shopping.filter(\.done).map(\.id), ["s1", "s2", "s4", "s5"])
    }

    func testAddReplacesTemporaryIdAndReconcilesRevWithoutRefetch() async {
        let store = await loaded()
        let requestsBefore = server.requests.count
        let added = await store.addItem(ShoppingDraft(name: "Butter", qty: 2, note: "salted"))
        XCTAssertTrue(added)
        let item = store.state?.shopping.last
        XCTAssertEqual(item?.name, "Butter")
        XCTAssertEqual(item?.qty, 2)
        XCTAssertEqual(item?.id.hasPrefix("local-"), false)
        XCTAssertEqual(store.state?.shopping.filter { $0.name == "Butter" }.count, 1)
        XCTAssertEqual(store.state?.rev, server.revision)
        XCTAssertEqual(server.requests.count, requestsBefore + 1)
    }

    func testRevGapTriggersFullRefresh() async {
        let gate = GatedTransport(server)
        let store = await loaded(gate)
        gate.hold()
        let task = Task { await store.setItem(id: "s1", done: true) }
        await waitUntil { gate.heldCount == 1 }
        server.changeFromFrame { $0.append(["id": "s99", "name": "Butter", "qty": 1, "note": "", "done": false]) }
        gate.release()
        _ = await task.value
        XCTAssertEqual(store.state?.rev, 44)
        XCTAssertEqual(store.state?.shopping.contains { $0.id == "s99" }, true)
        XCTAssertEqual(store.state?.shopping.first { $0.id == "s1" }?.done, true)
        XCTAssertEqual(server.requests.last?.path, "/v1/state")
    }

    func testMutationWithoutRevInResponseFallsBackToRefresh() async {
        let transport = ScriptedTransport([
            .status(200, #"{"rev":5,"shopping":[{"id":"s1","name":"Milk","qty":1,"note":"","done":false}]}"#),
            .status(204, ""),
            .status(200, #"{"rev":6,"shopping":[]}"#),
        ])
        let store = await loaded(transport)
        let deleted = await store.deleteItem(id: "s1")
        XCTAssertTrue(deleted)
        XCTAssertEqual(store.state?.rev, 6)
        XCTAssertEqual(transport.calls.map { $0.request.httpMethod }, ["GET", "DELETE", "GET"])
    }

    func testRejectedMutationRollsBackAndExplains() async {
        let store = await loaded()
        let before = store.state
        let added = await store.addItem(ShoppingDraft(name: "Too many", qty: 500))
        XCTAssertFalse(added)
        XCTAssertEqual(store.state, before)
        XCTAssertEqual(store.notice, "The frame didn't accept that. Check what you entered.")
        XCTAssertEqual(store.link, .online)
    }

    func testOfflineMutationRollsBackAndMarksOffline() async {
        let store = await loaded()
        let before = store.state
        server.setUnreachable(true)
        let ticked = await store.setItem(id: "s1", done: true)
        XCTAssertFalse(ticked)
        XCTAssertEqual(store.state, before)
        XCTAssertEqual(store.link, .offline)
        XCTAssertNil(store.notice)
    }

    func testOfflineStoreRelocatesFrameBeforeNextRequest() async {
        let store = await loaded()
        server.setUnreachable(true)
        await store.poll()
        XCTAssertEqual(store.link, .offline)
        server.setUnreachable(false)
        var asked = 0
        store.relocate = {
            asked += 1
            return URL(string: "https://192.168.1.77:9000")
        }
        await store.poll()
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(store.link, .online)
        XCTAssertEqual(server.requests.last?.url.host, "192.168.1.77")
        XCTAssertEqual(server.requests.last?.url.port, 9000)
        await store.poll()
        XCTAssertEqual(asked, 1)
    }

    func testRevokedTokenReportsUnauthorizedOnce() async {
        let store = await loaded()
        var revoked = 0
        store.onUnauthorized = { revoked += 1 }
        server.revokeAll()
        await store.poll()
        XCTAssertEqual(revoked, 1)
        let before = store.state
        let ticked = await store.setItem(id: "s1", done: true)
        XCTAssertFalse(ticked)
        XCTAssertEqual(revoked, 2)
        XCTAssertEqual(store.state, before)
    }

    func testChoreCompletionUsesFrameLocalDate() async {
        let store = await loaded()
        XCTAssertEqual(store.today?.date, "2026-10-11")
        XCTAssertEqual(store.today?.doneCount, 2)
        XCTAssertEqual(store.today?.total, 6)
        await store.setChore(id: "c2", done: true)
        XCTAssertEqual(server.requests.last?.path, "/v1/chores/c2/done")
        XCTAssertEqual(try? JSONSerialization.jsonObject(with: server.requests.last?.body ?? Data()) as? NSDictionary, ["date": "2026-10-11", "done": true])
        XCTAssertEqual(store.today?.doneCount, 3)
        await store.setChore(id: "c2", done: false)
        XCTAssertEqual(store.today?.doneCount, 2)
        XCTAssertEqual(store.state?.chores.first { $0.id == "c2" }?.done, [])
        XCTAssertEqual(store.state?.rev, server.revision)
    }

    func testChoreAddEditDelete() async {
        let store = await loaded()
        await store.addChore(ChoreDraft(title: "Sweep", emoji: "🧹", personId: "p3", days: [0, 6]))
        let created = store.state?.chores.last
        XCTAssertEqual(created?.title, "Sweep")
        XCTAssertEqual(created?.personId, "p3")
        XCTAssertEqual(created?.days, [0, 6])
        guard let id = created?.id else { return XCTFail("no chore") }
        await store.updateChore(id: id, ChoreDraft(title: "Sweep porch", emoji: "", personId: nil, days: []))
        let edited = store.state?.chores.first { $0.id == id }
        XCTAssertEqual(edited?.title, "Sweep porch")
        XCTAssertNil(edited?.personId)
        XCTAssertEqual(edited?.emoji, "")
        await store.deleteChore(id: id)
        XCTAssertEqual(store.state?.chores.contains { $0.id == id }, false)
        XCTAssertEqual(store.state?.rev, server.revision)
        XCTAssertNil(store.notice)
    }

    func testPeopleAddEditDeleteUnassignsChores() async {
        let store = await loaded()
        await store.addPerson(name: "Ada", color: "#44758A")
        XCTAssertEqual(store.state?.people.last?.name, "Ada")
        await store.updatePerson(Person(id: "p1", name: "Maya B", color: "#9A513B"))
        XCTAssertEqual(store.state?.people.first?.name, "Maya B")
        await store.deletePerson(id: "p1")
        XCTAssertEqual(store.state?.people.contains { $0.id == "p1" }, false)
        XCTAssertNil(store.state?.chores.first { $0.id == "c1" }?.personId)
        await store.refresh()
        XCTAssertNil(store.state?.chores.first { $0.id == "c1" }?.personId)
        XCTAssertEqual(store.today?.groups.last?.chores.contains { $0.chore.id == "c1" }, true)
    }

    func testShoppingEditTickDeleteClear() async {
        let store = await loaded()
        await store.updateItem(id: "s1", ShoppingDraft(name: "Oat milk", qty: 3, note: "barista"))
        XCTAssertEqual(store.state?.shopping.first, ShoppingItem(id: "s1", name: "Oat milk", qty: 3, note: "barista", done: false))
        await store.setItem(id: "s1", done: true)
        await store.deleteItem(id: "s2")
        XCTAssertEqual(store.state?.shopping.map(\.id), ["s1", "s3", "s4", "s5"])
        await store.clearDoneItems()
        XCTAssertEqual(store.state?.shopping.map(\.id), ["s3"])
        XCTAssertEqual(server.requests.last?.path, "/v1/shopping/clear-done")
        XCTAssertEqual(store.state?.rev, server.revision)
    }

    func testSettingsAndCalendars() async {
        let store = await loaded()
        await store.setAppearance(FrameAppearance(palette: "ocean", mode: "dark"))
        XCTAssertEqual(store.state?.settings.appearance, FrameAppearance(palette: "ocean", mode: "dark"))
        await store.setLocation(FrameLocation(name: "Pune", latitude: 18.52, longitude: 73.86, timezone: "Asia/Kolkata"))
        XCTAssertEqual(store.state?.settings.location?.timezone, "Asia/Kolkata")
        let added = await store.addCalendar(name: "Work", color: "#526747", url: "https://calendar.google.com/calendar/ical/x/private-abc/basic.ics")
        XCTAssertTrue(added)
        XCTAssertEqual(store.state?.calendars.map(\.name), ["Family", "School", "Work"])
        let rejected = await store.addCalendar(name: "Bad", color: "#526747", url: "http://example.com/feed")
        XCTAssertFalse(rejected)
        XCTAssertEqual(store.state?.calendars.count, 3)
        XCTAssertEqual(store.notice, "The frame didn't accept that. Check what you entered.")
        await store.deleteCalendar(id: "k1")
        XCTAssertEqual(store.state?.calendars.map(\.name), ["School", "Work"])
        await store.refresh()
        XCTAssertEqual(store.state?.settings.appearance.palette, "ocean")
        XCTAssertEqual(store.state?.settings.location?.name, "Pune")
    }

    func testPhotoUploadListAndDelete() async throws {
        let store = await loaded()
        await store.loadPhotos()
        XCTAssertEqual(store.photos.count, 6)
        let source = makeImage(width: 3200, height: 1800)
        await store.uploadPhotos([source, source])
        XCTAssertNil(store.upload)
        XCTAssertNil(store.notice)
        XCTAssertEqual(store.photos.count, 7)
        XCTAssertEqual(store.state?.photos.count, 7)
        let uploads = server.requests.filter { $0.method == "POST" && $0.path == "/v1/photos" }
        XCTAssertEqual(uploads.count, 2)
        XCTAssertEqual(uploads[0].headers["Content-Type"], "image/jpeg")
        let size = try XCTUnwrap(ImagePreparation.pixelSize(of: try XCTUnwrap(uploads[0].body)))
        XCTAssertEqual(size.width, 2560)
        let newest = try XCTUnwrap(store.photos.first)
        XCTAssertEqual(newest.id.count, 64)
        let stored = try await store.photoData(id: newest.id)
        XCTAssertEqual(stored, uploads[0].body)
        await store.deletePhoto(id: newest.id)
        XCTAssertEqual(store.photos.count, 6)
        XCTAssertEqual(store.state?.photos.count, 6)
    }

    func testUnreadablePhotoIsCountedNotUploaded() async {
        let store = await loaded()
        await store.uploadPhotos([Data("nope".utf8), makeImage(width: 200, height: 200), makeImage(width: 640, height: 480)])
        XCTAssertEqual(store.notice, "2 photos couldn't be added.")
        XCTAssertEqual(server.requests.filter { $0.method == "POST" && $0.path == "/v1/photos" }.count, 1)
        XCTAssertEqual(store.state?.photos.count, 7)
    }

    func testConnectionResetMidUploadSkipsThatPhotoAndKeepsGoing() async {
        let transport = ScriptedTransport([
            .status(200, #"{"rev":1}"#),
            .failure(URLError(.networkConnectionLost)),
            .status(200, #"{"rev":2,"photo":{"id":"aa","addedAt":"2026-10-11T10:00:00Z"}}"#),
            .status(200, #"{"rev":2,"photos":{"count":1}}"#),
            .status(200, #"[{"id":"aa","addedAt":"2026-10-11T10:00:00Z"}]"#),
        ])
        let store = await loaded(transport)
        await store.uploadPhotos([makeImage(width: 640, height: 480), makeImage(width: 800, height: 600)])
        XCTAssertEqual(store.notice, "One photo couldn't be added.")
        XCTAssertEqual(store.link, .online)
        XCTAssertEqual(store.photos.map(\.id), ["aa"])
        XCTAssertEqual(transport.calls.map { $0.request.httpMethod }, ["GET", "POST", "POST", "GET", "GET"])
    }

    func testFailedPhotoDeleteRestoresList() async {
        let store = await loaded()
        await store.loadPhotos()
        server.setUnreachable(true)
        await store.deletePhoto(id: store.photos[0].id)
        XCTAssertEqual(store.photos.count, 6)
        XCTAssertEqual(store.link, .offline)
    }

    func testDevicesMarkThisPhoneAndOnlyItCanBeRemoved() async throws {
        let store = await loaded()
        await store.loadDevices()
        XCTAssertEqual(store.devices.map(\.name), ["Karan's iPhone", "Hallway tablet"])
        XCTAssertEqual(store.devices.map(\.isSelf), [true, false])
        XCTAssertEqual(store.thisDevice?.id, "d1")
        XCTAssertNotNil(store.thisDevice?.lastSeenDate)
        let api = FrameAPI(baseURL: DemoFrameServer.address, token: DemoFrameServer.demoToken, transport: server)
        do {
            try await api.removeDevice(id: "d2")
            XCTFail("another phone must not be removable from the app")
        } catch {
            XCTAssertEqual(error as? FrameError, .api(status: 403, code: "forbidden"))
        }
        let unpaired = await store.unpairThisPhone()
        XCTAssertTrue(unpaired)
        XCTAssertEqual(server.requests.last?.method, "DELETE")
        XCTAssertEqual(server.requests.last?.path, "/v1/devices/d1")
        var revoked = false
        store.onUnauthorized = { revoked = true }
        await store.poll()
        XCTAssertTrue(revoked)
    }

    func testUnpairLoadsDevicesFirstWhenNeeded() async {
        let store = await loaded()
        let unpaired = await store.unpairThisPhone()
        XCTAssertTrue(unpaired)
        XCTAssertEqual(server.requests.suffix(2).map(\.method), ["GET", "DELETE"])
    }

    func testRevisionAtTheIntegerLimitDoesNotTrap() async {
        let transport = ScriptedTransport([
            .status(200, #"{"rev":9223372036854775807,"shopping":[{"id":"s1","name":"Milk","qty":1,"note":"","done":false}]}"#),
            .status(200, #"{"rev":1,"item":{"id":"s1","name":"Milk","qty":1,"note":"","done":true}}"#),
            .status(200, #"{"rev":1,"shopping":[{"id":"s1","name":"Milk","qty":1,"note":"","done":true}]}"#),
        ])
        let store = await loaded(transport)
        XCTAssertEqual(store.state?.rev, Int.max)
        let ticked = await store.setItem(id: "s1", done: true)
        XCTAssertTrue(ticked)
        XCTAssertEqual(store.state?.rev, 1)
        XCTAssertEqual(transport.calls.count, 3)
    }

    func testPinMismatchMidSessionGoesOfflineAndKeepsEverything() async {
        let transport = ScriptedTransport([.status(200, #"{"rev":5}"#), .failure(FrameError.pinMismatch)])
        let store = await loaded(transport)
        var revoked = false
        store.onUnauthorized = { revoked = true }
        await store.poll()
        XCTAssertEqual(store.link, .offline)
        XCTAssertFalse(revoked)
        XCTAssertEqual(store.state?.rev, 5)
    }

    func testPollingLoopStopsWhenCancelled() async {
        let store = await loaded()
        let before = server.requests.count
        let task = Task { await store.runPolling(every: .milliseconds(10)) }
        await waitUntil { self.server.requests.count >= before + 2 }
        task.cancel()
        await task.value
        let settled = server.requests.count
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(server.requests.count, settled)
        XCTAssertGreaterThanOrEqual(settled, before + 2)
        XCTAssertTrue(server.requests.suffix(2).allSatisfy { $0.query == "since=42" })
    }
}
