import XCTest

final class LiveFrameUITests: XCTestCase {
    private let control = URL(string: "http://127.0.0.1:18932")!
    private let address = "127.0.0.1:18931"

    override func setUp() {
        continueAfterFailure = false
    }

    private func controlJSON(_ path: String, post: Bool = false) -> [String: Any]? {
        var request = URLRequest(url: control.appendingPathComponent(path))
        request.httpMethod = post ? "POST" : "GET"
        request.timeoutInterval = 2
        let done = DispatchSemaphore(value: 0)
        var result: [String: Any]?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            result = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            done.signal()
        }.resume()
        done.wait()
        return result
    }

    private func waitForCode() -> String? {
        for _ in 0..<40 {
            if let pairing = controlJSON("state")?["pairing"] as? [String: Any], let code = pairing["code"] as? String { return code }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }

    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SKYLIT_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.count > 0 { app.swipeDown() }
    }

    private func switchTab(_ name: String, in app: XCUIApplication) {
        dismissKeyboard(app)
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            app.swipeDown()
        }
    }

    private func unpair(_ app: XCUIApplication) {
        switchTab("Frame", in: app)
        let unpair = app.buttons["Unpair this phone"]
        reveal(unpair, in: app)
        unpair.tap()
        app.buttons["Unpair"].tap()
        XCTAssertTrue(app.textFields["192.168.1.20:8765"].waitForExistence(timeout: 8))
    }

    private func leaveAnyFrame(_ app: XCUIApplication) {
        if app.tabBars.buttons["Shopping"].waitForExistence(timeout: 8) {
            unpair(app)
            return
        }
        let different = app.buttons["Use a different frame"]
        guard different.exists else { return }
        different.tap()
        let field = app.textFields["192.168.1.20:8765"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(address + "\n")
        if app.tabBars.buttons["Shopping"].waitForExistence(timeout: 10) { unpair(app) }
    }

    func testPairManageEveryTabAndUnpairAgainstTheDevServer() throws {
        try XCTSkipIf(controlJSON("state") == nil, "Start scripts/dev_server.py --port 18931 --pair-window --auto-approve 5 --control-port 18932")
        _ = controlJSON("open", post: true)
        let app = XCUIApplication()
        app.launch()
        leaveAnyFrame(app)

        let name = app.textFields["Maya's iPhone"]
        if !name.exists {
            let field = app.textFields["192.168.1.20:8765"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(address + "\n")
        }
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        app.buttons["Pair"].tap()
        let code = try XCTUnwrap(waitForCode(), "The frame never showed a code")
        let entry = app.textFields["Pairing code"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.6)
        entry.typeText(code)
        if app.staticTexts["Waiting for the tap on the frame"].waitForExistence(timeout: 2) { snap("live-confirming") }
        XCTAssertTrue(app.tabBars.buttons["Shopping"].waitForExistence(timeout: 25))
        snap("live-paired")
        app.tabBars.buttons["Shopping"].tap()

        let tag = String(Int(Date().timeIntervalSince1970) % 100000)
        let add = app.textFields["Add an item"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        add.typeText("Eggs \(tag)\n")
        dismissKeyboard(app)
        let eggs = app.buttons["Eggs \(tag)"]
        XCTAssertTrue(eggs.waitForExistence(timeout: 5))
        eggs.tap()
        XCTAssertTrue(app.buttons["Clear completed"].waitForExistence(timeout: 5))
        snap("live-shopping")
        eggs.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Removed Eggs \(tag)"].waitForExistence(timeout: 5))
        app.buttons["Undo"].tap()
        XCTAssertTrue(eggs.waitForExistence(timeout: 5))
        eggs.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Removed Eggs \(tag)"].waitForExistence(timeout: 5))

        switchTab("Chores", in: app)
        let addChore = app.textFields["Add a chore"]
        XCTAssertTrue(addChore.waitForExistence(timeout: 5))
        addChore.tap()
        addChore.typeText("Sweep \(tag)\n")
        dismissKeyboard(app)
        let sweep = app.buttons["Sweep \(tag)"]
        XCTAssertTrue(sweep.waitForExistence(timeout: 5))
        sweep.tap()
        XCTAssertTrue(sweep.waitForExistence(timeout: 5))
        XCTAssertEqual(sweep.value as? String, "Done")

        switchTab("Frame", in: app)
        XCTAssertTrue(app.buttons["Sage"].waitForExistence(timeout: 5))
        app.buttons["Sage"].tap()
        XCTAssertTrue(app.buttons["Sage"].waitForExistence(timeout: 5))
        snap("live-frame-sage")
        let addCalendar = app.buttons["Add a calendar"]
        reveal(addCalendar, in: app)
        addCalendar.tap()
        let calendarName = app.textFields["Family"]
        XCTAssertTrue(calendarName.waitForExistence(timeout: 5))
        calendarName.tap()
        calendarName.typeText("Work \(tag)")
        let link = app.textFields["Secret address in iCal format"]
        link.tap()
        let url = "https://calendar.google.com/calendar/ical/x%40gmail.com/private-\(tag)/basic.ics"
        link.typeText(url)
        XCTAssertEqual(link.value as? String, url)
        XCTAssertEqual(calendarName.value as? String, "Work \(tag)")
        dismissKeyboard(app)
        let addButton = app.buttons["Add calendar"]
        reveal(addButton, in: app)
        XCTAssertTrue(addButton.isEnabled)
        addButton.tap()
        let work = app.staticTexts["Work \(tag)"]
        XCTAssertTrue(work.waitForExistence(timeout: 15))
        work.press(forDuration: 1.2)
        let removeFromFrame = app.buttons["Remove from Frame"]
        XCTAssertTrue(removeFromFrame.waitForExistence(timeout: 5))
        removeFromFrame.tap()
        let remove = app.buttons["Remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertFalse(work.waitForExistence(timeout: 3))

        let linen = app.buttons["Linen"]
        reveal(linen, in: app)
        linen.tap()
        unpair(app)
        snap("live-unpaired")
    }
}
