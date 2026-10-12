import XCTest
@testable import SkylitCore

final class IntegrationTests: XCTestCase {
    private static let deviceName = "Skylit iOS integration test"

    private func client() async throws -> FrameAPI {
        let environment = ProcessInfo.processInfo.environment
        guard let text = environment["SKYLIT_TEST_URL"], let url = FrameAddress.parse(text) else {
            throw XCTSkip("Set SKYLIT_TEST_URL (and SKYLIT_TEST_CODE or SKYLIT_TEST_TOKEN) to run against a real frame or dev server")
        }
        var api = FrameAPI(baseURL: url, transport: URLSessionTransport())
        if let token = environment["SKYLIT_TEST_TOKEN"] {
            api.token = token
        } else if let code = environment["SKYLIT_TEST_CODE"] {
            api.token = try await api.pairFinish(code: code, deviceName: Self.deviceName).token
        } else {
            throw XCTSkip("Set SKYLIT_TEST_CODE (after POST /v1/pair/start) or SKYLIT_TEST_TOKEN")
        }
        return api
    }

    func testWholeContractAgainstLiveServer() async throws {
        let api = try await client()

        let info = try await api.info()
        XCTAssertEqual(info.v, 1)
        XCTAssertFalse(info.frameId.isEmpty)

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
            guard case .api(400, "bad_request", _) = FrameError.from(error) else { return XCTFail("expected 400 bad_request, got \(error)") }
        }
        do {
            _ = try await api.deleteChore(id: "does-not-exist")
            XCTFail("unknown chore should be 404")
        } catch {
            guard case .api(404, "not_found", _) = FrameError.from(error) else { return XCTFail("expected 404 not_found, got \(error)") }
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
        XCTAssertFalse(devices.isEmpty)
        if let mine = devices.first(where: { $0.name == Self.deviceName }) {
            try await api.revokeDevice(id: mine.id)
            do {
                _ = try await api.state()
                XCTFail("revoked token should be 401")
            } catch {
                XCTAssertEqual(FrameError.from(error), .unauthorized)
            }
        }
    }
}
