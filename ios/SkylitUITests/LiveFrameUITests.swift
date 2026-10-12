import XCTest
import SkylitCore

final class LiveFrameUITests: XCTestCase {
    private struct Ports {
        let api: Int
        let control: Int
        let supervisor: Int
    }

    private var ports: Ports!
    private var app: XCUIApplication!
    private var address: String { "127.0.0.1:\(ports.api)" }
    private var frameURL: URL { URL(string: "https://\(address)")! }

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        guard let api = env["SKYLIT_LIVE_API"].flatMap(Int.init), let control = env["SKYLIT_LIVE_CONTROL"].flatMap(Int.init),
              let supervisor = env["SKYLIT_LIVE_SUPERVISOR"].flatMap(Int.init) else {
            throw XCTSkip("Run ios/scripts/live_frame_test.py; it starts the dev frame and sets SKYLIT_LIVE_* for this test")
        }
        ports = Ports(api: api, control: control, supervisor: supervisor)
    }

    private func json(_ port: Int, _ path: String) -> [String: Any]? {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/\(path)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        let done = DispatchSemaphore(value: 0)
        var result: [String: Any]?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            result = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            done.signal()
        }.resume()
        done.wait()
        return result
    }

    @discardableResult private func control(_ path: String) -> [String: Any]? { json(ports.control, path) }
    @discardableResult private func supervise(_ path: String) -> [String: Any]? { json(ports.supervisor, path) }

    private func frameState() -> [String: Any] { control("state") ?? [:] }
    private func pairingPhase() -> String { (frameState()["pairing"] as? [String: Any])?["phase"] as? String ?? "" }

    private func waitForPhase(_ phase: String, timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pairingPhase() == phase { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    private func shownCode() throws -> String {
        XCTAssertTrue(waitForPhase("code"), "The frame never showed a code; phase is \(pairingPhase())")
        return try XCTUnwrap((frameState()["pairing"] as? [String: Any])?["code"] as? String)
    }

    private func pick() throws -> String { try XCTUnwrap(frameState()["pick"] as? String) }

    private func decoy() throws -> String {
        let numbers = try XCTUnwrap((frameState()["pairing"] as? [String: Any])?["numbers"] as? [String])
        return try XCTUnwrap(numbers.first { $0 != (try? pick()) })
    }

    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SKYLIT_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func dismissKeyboard() {
        app.dismissKeyboardIfShown()
    }

    private func finishAdding(_ field: XCUIElement) {
        field.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Return on an empty add field dismisses the keyboard")
    }

    private func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    override func tearDown() {
        if app != nil { snap("live-last-screen") }
    }

    private func switchTab(_ name: String) {
        dismissKeyboard()
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        for _ in 0..<3 where !tab.isSelected {
            tab.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(tab.isSelected, "\(name) tab did not open")
    }

    private func reveal(_ element: XCUIElement) {
        let list = app.collectionViews.firstMatch
        for _ in 0..<6 where !(element.exists && element.isHittable) { list.swipeUp() }
        for _ in 0..<8 where !(element.exists && element.isHittable) { list.swipeDown() }
        XCTAssertTrue(element.isHittable, "\(element) never became hittable")
    }

    private var addressField: XCUIElement { app.textFields["192.168.1.20:8765"] }
    private var nameField: XCUIElement { app.textFields["Maya's iPhone"] }
    private var shoppingTab: XCUIElement { app.tabBars.buttons["Shopping"] }

    private func connectByAddress() {
        XCTAssertTrue(addressField.waitForExistence(timeout: 8))
        addressField.tap()
        addressField.typeText(address + "\n")
    }

    private func leaveAnyFrame() {
        if shoppingTab.waitForExistence(timeout: 6) {
            unpair()
            return
        }
        let different = app.buttons["Use a different frame"]
        if different.waitForExistence(timeout: 2) { different.tap() }
        XCTAssertTrue(addressField.waitForExistence(timeout: 5))
    }

    private func unpair() {
        switchTab("Frame")
        let unpair = app.buttons["Unpair this phone"]
        reveal(unpair)
        unpair.tap()
        app.buttons["Unpair"].tap()
        XCTAssertTrue(addressField.waitForExistence(timeout: 8))
    }

    private func openPairingSheet() {
        connectByAddress()
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
    }

    private func beginPairing() throws -> String {
        control("open")
        XCTAssertTrue(waitForPhase("waiting", timeout: 5))
        XCTAssertTrue(app.buttons["Pair"].waitForExistence(timeout: 5))
        app.buttons["Pair"].tap()
        let code = try shownCode()
        XCTAssertTrue(app.textFields["Pairing code"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        return code
    }

    private func typeCode(_ code: String) {
        app.textFields["Pairing code"].typeText(code)
    }

    private func wrongCode(_ right: String) -> String {
        String(right.map { $0 == "0" ? "1" : "0" })
    }

    private func tryAgain() {
        let again = app.buttons["Try again"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap()
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
    }

    private func expectConfirming() throws -> String {
        let pick = try pick()
        let confirming = app.staticTexts["Tap \(pick) on the frame"]
        if !confirming.waitForExistence(timeout: 8) {
            snap("live-no-confirming")
            XCTFail("no confirmation step; frame=\(frameState()) sheet=\(app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | "))")
        }
        return pick
    }

    private func expectPaired() {
        XCTAssertTrue(shoppingTab.waitForExistence(timeout: 25))
    }

    @MainActor
    private func pairHelperDevice(named name: String) async throws -> FrameAPI {
        let connector = TLSConnector()
        let pairing = connector.pairing()
        let tokens = InMemoryTokenStore()
        let flow = PairingFlow(frameName: "Skylit", api: FrameAPI(baseURL: frameURL, transport: pairing),
                               probe: FrameAPI(baseURL: frameURL, transport: connector.probe()), fingerprint: { pairing.fingerprint },
                               tokens: tokens, names: DeviceNameStore(defaults: UserDefaults(suiteName: "live-helper")!, fallback: name),
                               pollInterval: .milliseconds(300))
        control("open")
        XCTAssertTrue(waitForPhase("waiting", timeout: 5))
        await flow.begin(name: name)
        XCTAssertEqual(flow.step, .enteringCode, flow.message ?? "")
        await flow.submit(code: try shownCode())
        control("tap/\(try pick())")
        let outcome = await flow.awaitResult()
        let result = try XCTUnwrap(outcome)
        return FrameAPI(baseURL: frameURL, token: result.credential.token, transport: connector.pinned(result.credential.fp))
    }

    @MainActor
    func testPairingEndingsDataFlowOutagesAndRestartAgainstTheDevFrame() async throws {
        app = XCUIApplication()
        app.launch()
        leaveAnyFrame()
        openPairingSheet()
        XCTAssertTrue(app.buttons["Pair"].waitForExistence(timeout: 5))
        app.buttons["Pair"].tap()
        XCTAssertTrue(text(containing: PairingFlow.windowText).waitForExistence(timeout: 8), "a closed window must say so")
        snap("live-window-closed")

        var code = try beginPairing()
        for _ in 0..<3 { typeCode(wrongCode(code)) }
        XCTAssertTrue(text(containing: PairingFlow.failureText).waitForExistence(timeout: 8))
        XCTAssertTrue(waitForPhase("cancelled", timeout: 5) || waitForPhase("idle", timeout: 1))
        snap("live-three-misses")
        tryAgain()

        code = try beginPairing()
        typeCode(code)
        _ = try expectConfirming()
        control("tap/\(try decoy())")
        XCTAssertTrue(text(containing: PairingFlow.cancelledText).waitForExistence(timeout: 10))
        snap("live-decoy")
        tryAgain()

        code = try beginPairing()
        typeCode(code)
        _ = try expectConfirming()
        control("cancel")
        XCTAssertTrue(text(containing: PairingFlow.cancelledText).waitForExistence(timeout: 10))
        tryAgain()

        code = try beginPairing()
        typeCode(code)
        _ = try expectConfirming()
        XCTAssertTrue(text(containing: PairingFlow.timeoutText).waitForExistence(timeout: 150), "the window must time out after two minutes")
        snap("live-window-timeout")
        tryAgain()

        code = try beginPairing()
        typeCode(code)
        let pick = try expectConfirming()
        XCUIDevice.shared.press(.home)
        try await Task.sleep(for: .seconds(2))
        app.activate()
        XCTAssertTrue(app.staticTexts["Tap \(pick) on the frame"].waitForExistence(timeout: 5))
        control("tap/\(pick)")
        expectPaired()
        snap("live-paired")

        shoppingTab.tap()
        let add = app.textFields["Add an item"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        for item in ["Eggs", "Milk", "Bread"] { add.typeText("\(item)\n") }
        XCTAssertTrue((add.value(forKey: "hasKeyboardFocus") as? Bool) == true)
        finishAdding(add)
        for item in ["Eggs", "Milk", "Bread"] { XCTAssertTrue(app.buttons[item].waitForExistence(timeout: 5)) }
        app.buttons["Eggs"].tap()
        XCTAssertTrue(app.buttons["Clear completed"].waitForExistence(timeout: 5))
        app.buttons["Milk"].swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        if delete.waitForExistence(timeout: 2) { delete.tap() }
        XCTAssertTrue(app.staticTexts["Removed Milk"].waitForExistence(timeout: 5))
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.buttons["Milk"].waitForExistence(timeout: 5))
        snap("live-shopping")

        let helper = try await pairHelperDevice(named: "Hallway tablet")
        _ = try await helper.addItem(ShoppingDraft(name: "From the tablet"))
        XCTAssertTrue(app.buttons["From the tablet"].waitForExistence(timeout: 15), "a change from another phone must show within a poll")
        let listed = try await helper.state()
        let fromTablet = try XCTUnwrap(listed?.shopping.first { $0.name == "From the tablet" })
        _ = try await helper.deleteItem(id: fromTablet.id)
        XCTAssertTrue(app.buttons["From the tablet"].waitForNonExistence(timeout: 15))

        switchTab("Chores")
        let addChore = app.textFields["Add a chore"]
        XCTAssertTrue(addChore.waitForExistence(timeout: 5))
        addChore.tap()
        addChore.typeText("Sweep\n")
        finishAdding(addChore)
        let sweep = app.buttons["Sweep"]
        XCTAssertTrue(sweep.waitForExistence(timeout: 5))
        sweep.tap()
        XCTAssertTrue(sweep.waitForExistence(timeout: 5))
        XCTAssertEqual(sweep.value as? String, "Done")

        switchTab("Frame")
        let addCalendar = app.buttons["Add a calendar"]
        reveal(addCalendar)
        addCalendar.tap()
        let calendarName = app.textFields["Family"]
        XCTAssertTrue(calendarName.waitForExistence(timeout: 5))
        calendarName.tap()
        calendarName.typeText("Work")
        let link = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR placeholderValue == %@", "Secret address in iCal format", "Paste the secret address")).firstMatch
        app.bringAboveKeyboard(link)
        link.tap()
        link.typeText("https://calendar.google.com/calendar/ical/x%40gmail.com/private-\(Int(Date().timeIntervalSince1970))/basic.ics")
        let addButton = app.buttons["Add calendar"]
        app.bringAboveKeyboard(addButton)
        XCTAssertTrue(addButton.isEnabled)
        addButton.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "adding a calendar puts the keyboard away")
        let work = app.staticTexts["Work"]
        XCTAssertTrue(work.waitForExistence(timeout: 15))
        work.press(forDuration: 1.2)
        let removeFromFrame = app.buttons["Remove from Frame"]
        XCTAssertTrue(removeFromFrame.waitForExistence(timeout: 5))
        removeFromFrame.tap()
        let remove = app.buttons["Remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(work.waitForNonExistence(timeout: 5))
        let devices = app.staticTexts["Hallway tablet"]
        reveal(devices)
        XCTAssertTrue(app.staticTexts["This phone"].exists)
        app.swipeDown()
        app.swipeDown()
        XCTAssertTrue(app.buttons["Sage"].waitForExistence(timeout: 5))
        app.buttons["Sage"].tap()
        XCTAssertTrue(app.buttons["Sage"].waitForExistence(timeout: 5))
        snap("live-frame-sage")

        supervise("pause")
        XCTAssertTrue(text(containing: "can't reach it right now").waitForExistence(timeout: 40), "a paused frame must show as unreachable")
        snap("live-frame-away")
        switchTab("Shopping")
        let addWhileAway = app.textFields["Add an item"]
        XCTAssertTrue(addWhileAway.waitForExistence(timeout: 5))
        addWhileAway.tap()
        addWhileAway.typeText("Butter\n")
        finishAdding(addWhileAway)
        supervise("resume")
        XCTAssertTrue(text(containing: "can't reach it right now").waitForNonExistence(timeout: 40), "the frame must come back on its own")
        let butter = app.buttons["Butter"]
        if butter.exists {
            let state = try await helper.state()
            XCTAssertTrue(state?.shopping.contains { $0.name == "Butter" } ?? false, "a row shown after reconnect must exist on the frame")
        }
        snap("live-frame-back")

        let before = frameState()["fp"] as? String
        supervise("restart")
        XCTAssertNotEqual(frameState()["fp"] as? String, before)
        XCTAssertTrue(text(containing: "claiming to be").waitForExistence(timeout: 40), "a frame with a new certificate must be refused")
        snap("live-new-certificate")
        switchTab("Frame")
        let different = app.buttons["Use a different frame"]
        reveal(different)
        different.tap()
        openPairingSheet()
        code = try beginPairing()
        typeCode(code)
        control("tap/\(try expectConfirming())")
        expectPaired()
        unpair()
        snap("live-unpaired")
    }
}
