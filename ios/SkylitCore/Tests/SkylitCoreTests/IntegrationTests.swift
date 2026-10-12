import XCTest
@testable import SkylitCore

final class IntegrationTests: XCTestCase {
    private static let deviceName = "iFramed You integration test"

    private func client() async throws -> FrameAPI {
        let environment = ProcessInfo.processInfo.environment
        guard let text = environment["SKYLIT_TEST_URL"], let url = FrameAddress.parse(text) else {
            throw XCTSkip("Set SKYLIT_TEST_URL to a frame or dev server whose pairing window is open and which approves the pick")
        }
        let probe = URLSessionTransport(.probe)
        let info = try await FrameAPI(baseURL: url, transport: probe).info()
        XCTAssertEqual(info.v, 2)
        let probed = try XCTUnwrap(probe.fingerprint)
        XCTAssertEqual(info.frameId, Pin.frameId(for: probed))
        if let expected = environment["SKYLIT_TEST_FP"] { XCTAssertEqual(probed, expected) }
        XCTAssertTrue(info.pairing, "Open the pairing window on the frame or dev server first")

        let transport = URLSessionTransport(.pairing)
        let pairing = FrameAPI(baseURL: url, transport: transport)
        let nP = try PairingCrypto.randomBytes(), token = try PairingCrypto.randomBytes()
        let started = try await pairing.pairStart(commit: PairingCrypto.sha256(nP), tokenHash: PairingCrypto.sha256(token), deviceName: Self.deviceName)
        let fp = try XCTUnwrap(transport.fingerprint)
        XCTAssertEqual(fp, probed)
        do {
            _ = try await FrameAPI(baseURL: url, transport: URLSessionTransport(.pairing))
                .pairStart(commit: PairingCrypto.sha256(nP), tokenHash: PairingCrypto.sha256(token), deviceName: "Second")
            XCTFail("a second start in one window should be 409")
        } catch {
            XCTAssertEqual(error as? FrameError, .api(status: 409, code: "pairing_busy"))
        }
        try await pairing.pairReveal(session: started.session, nP: Hex.encode(nP))
        let derived = PairingCrypto.derive(nP: nP, nF: try XCTUnwrap(Hex.decode(started.nF, bytes: 32)), fpRaw: try XCTUnwrap(Hex.decode(fp, bytes: 32)))
        print("SKYLIT pairing code \(derived.code) pick \(derived.pick) fingerprint \(fp)")
        var result: PairResult?
        for _ in 0..<120 where result == nil {
            result = try await pairing.pairResult(session: started.session)
            if result == nil { try await Task.sleep(for: .milliseconds(500)) }
        }
        XCTAssertEqual(try XCTUnwrap(result).frameId, Pin.frameId(for: fp))

        let wrongPin = FrameAPI(baseURL: url, token: Hex.encode(token), transport: URLSessionTransport(.pinned(String(repeating: "0", count: 64))))
        do {
            _ = try await wrongPin.state()
            XCTFail("a wrong pin must refuse the handshake")
        } catch {
            XCTAssertEqual(error as? FrameError, .pinMismatch)
        }
        return FrameAPI(baseURL: url, token: Hex.encode(token), transport: URLSessionTransport(.pinned(fp)))
    }

    func testWholeContractAgainstLiveServer() async throws {
        let api = try await client()

        let initialReply = try await api.state()
        let initial = try XCTUnwrap(initialReply)
        let unchanged = try await api.state(since: initial.rev)
        XCTAssertNil(unchanged, "since=<current rev> should answer 304")

        let personReply = try await api.addPerson(name: "Integration Ida", color: "#44758A").person
        let person = try XCTUnwrap(personReply)
        let renamed = try await api.updatePerson(id: person.id, name: "Integration Ida B")
        XCTAssertEqual(renamed.person?.name, "Integration Ida B")

        let choreReply = try await api.addChore(ChoreDraft(title: "Integration chore", emoji: "🧪", personId: person.id, days: [0, 6])).chore
        let chore = try XCTUnwrap(choreReply)
        XCTAssertEqual(chore.personId, person.id)
        XCTAssertEqual(chore.days.sorted(), [0, 6])
        let edited = try await api.updateChore(id: chore.id, ChoreDraft(title: "Integration chore 2", emoji: "", personId: nil, days: []))
        XCTAssertEqual(edited.chore?.title, "Integration chore 2")
        XCTAssertNil(edited.chore?.personId)
        let done = try await api.setChoreDone(id: chore.id, date: "2026-10-11", done: true)
        XCTAssertEqual(done.chore?.done.contains("2026-10-11"), true)
        let undone = try await api.setChoreDone(id: chore.id, date: "2026-10-11", done: false)
        XCTAssertEqual(undone.chore?.done.contains("2026-10-11"), false)

        let itemReply = try await api.addItem(ShoppingDraft(name: "Integration milk", qty: 2, note: "oat")).item
        let item = try XCTUnwrap(itemReply)
        XCTAssertEqual(item.qty, 2)
        let ticked = try await api.updateItem(id: item.id, done: true)
        XCTAssertEqual(ticked.item?.done, true)
        let secondReply = try await api.addItem(ShoppingDraft(name: "Integration bread")).item
        let second = try XCTUnwrap(secondReply)
        _ = try await api.clearDoneItems()
        let afterClearReply = try await api.state()
        let afterClear = try XCTUnwrap(afterClearReply)
        XCTAssertFalse(afterClear.shopping.contains { $0.id == item.id })
        XCTAssertTrue(afterClear.shopping.contains { $0.id == second.id })
        _ = try await api.deleteItem(id: second.id)

        _ = try await api.setAppearance(FrameAppearance(palette: "ocean", mode: "dark"))
        _ = try await api.setLocation(FrameLocation(name: "Calgary", latitude: 51.05, longitude: -114.07, timezone: "America/Edmonton"))
        let configuredReply = try await api.state()
        let configured = try XCTUnwrap(configuredReply)
        XCTAssertEqual(configured.settings.appearance, FrameAppearance(palette: "ocean", mode: "dark"))
        XCTAssertEqual(configured.settings.location?.name, "Calgary")
        _ = try await api.setAppearance(initial.settings.appearance)
        if let location = initial.settings.location { _ = try await api.setLocation(location) }

        do {
            _ = try await api.addItem(ShoppingDraft(name: "Too many", qty: 500))
            XCTFail("qty 500 should be rejected")
        } catch {
            XCTAssertEqual(FrameError.from(error), .api(status: 400, code: "bad_request"))
        }
        do {
            _ = try await api.deleteChore(id: "does-not-exist")
            XCTFail("unknown chore should be 404")
        } catch {
            XCTAssertEqual(FrameError.from(error), .api(status: 404, code: "not_found"))
        }

        let jpeg = try ImagePreparation.jpeg(from: makeImage(width: 3000, height: 2000))
        let uploadedReply = try await api.uploadPhoto(jpeg).photo
        let uploaded = try XCTUnwrap(uploadedReply)
        XCTAssertEqual(uploaded.id.count, 64)
        let again = try await api.uploadPhoto(jpeg)
        XCTAssertEqual(again.photo?.id, uploaded.id)
        let listed = try await api.photos()
        XCTAssertEqual(listed.filter { $0.id == uploaded.id }.count, 1)
        let stored = try await api.photoData(id: uploaded.id)
        XCTAssertEqual(Array(stored.prefix(2)), [0xFF, 0xD8])
        _ = try await api.deletePhoto(id: uploaded.id)
        let afterDelete = try await api.photos()
        XCTAssertFalse(afterDelete.contains { $0.id == uploaded.id })

        _ = try await api.deleteChore(id: chore.id)
        _ = try await api.deletePerson(id: person.id)
        let finalReply = try await api.state()
        let final = try XCTUnwrap(finalReply)
        XCTAssertGreaterThan(final.rev, initial.rev)
        XCTAssertFalse(final.people.contains { $0.id == person.id })

        var stranger = api
        stranger.token = String(repeating: "0", count: 64)
        do {
            _ = try await stranger.state()
            XCTFail("unknown token should be 401")
        } catch {
            XCTAssertEqual(FrameError.from(error), .unauthorized)
        }

        let devices = try await api.devices()
        let mine = try XCTUnwrap(devices.first(where: \.isSelf))
        XCTAssertEqual(mine.name, Self.deviceName)
        XCTAssertNotNil(mine.pairedDate)
        if let other = devices.first(where: { !$0.isSelf }) {
            do {
                try await api.removeDevice(id: other.id)
                XCTFail("another device should be 403")
            } catch {
                XCTAssertEqual(FrameError.from(error), .api(status: 403, code: "forbidden"))
            }
        }
        try await api.removeDevice(id: mine.id)
        do {
            _ = try await api.state()
            XCTFail("a removed phone's token should be 401")
        } catch {
            XCTAssertEqual(FrameError.from(error), .unauthorized)
        }
    }
}
