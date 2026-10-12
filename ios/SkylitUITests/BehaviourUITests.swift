import XCTest

final class BehaviourUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ screen: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoFrame", "YES", "-demoScreen", screen] + extra
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launch()
        return app
    }

    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) == true
    }

    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SKYLIT_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func deleteBySwipe(_ row: XCUIElement, in app: XCUIApplication) {
        row.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        if delete.waitForExistence(timeout: 2) { delete.tap() }
    }

    private func paste(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        UIPasteboard.general.string = text
        field.tap()
        let paste = app.menuItems["Paste"]
        for _ in 0..<3 where !paste.exists {
            field.press(forDuration: 1.2)
            _ = paste.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(paste.exists, "the edit menu never offered Paste")
        paste.tap()
    }

    func testRapidEntryKeepsFocusAndScrollsTheNewestRowAboveTheKeyboard() {
        let app = launch("shopping")
        let field = app.textFields["Add an item"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let names = (1...12).map { "Item \($0)" }
        for name in names { field.typeText("\(name)\n") }
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists)
        XCTAssertTrue(hasKeyboardFocus(field))
        let newest = app.buttons["Item 12"]
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        XCTAssertTrue(newest.isHittable)
        XCTAssertLessThanOrEqual(newest.frame.maxY, keyboard.frame.minY)
        XCTAssertGreaterThan(newest.frame.minY, field.frame.maxY)
        XCTAssertLessThan(newest.frame.minY, app.buttons["Item 11"].frame.minY)
        snap("rapid-entry-newest-visible")
        field.typeText("\n")
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5), "Return on an empty field dismisses the keyboard")
        XCTAssertFalse(hasKeyboardFocus(field))
        XCTAssertTrue(app.tabBars.buttons["Chores"].isHittable)
    }

    func testUndoAndNoticeToastsStackWithoutOverlapping() {
        let app = launch("shopping", ["-demoNotice", "The frame restarted."])
        let milk = app.buttons["Milk, 2"]
        XCTAssertTrue(milk.waitForExistence(timeout: 5))
        deleteBySwipe(milk, in: app)
        let undo = app.staticTexts["Removed Milk"]
        let notice = app.staticTexts["The frame restarted."]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.exists)
        XCTAssertFalse(undo.frame.intersects(notice.frame))
        let tabBar = app.tabBars.firstMatch
        XCTAssertFalse(undo.frame.intersects(tabBar.frame))
        XCTAssertFalse(notice.frame.intersects(tabBar.frame))
        snap("toasts-stacked")
        app.buttons["Undo"].tap()
        XCTAssertTrue(milk.waitForExistence(timeout: 5))
    }

    func testRemovalOnTheFrameReturnsToPairingWithAnExplanation() {
        let app = launch("shopping", ["-demoRevoke", "YES"])
        XCTAssertTrue(app.tabBars.buttons["Shopping"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This phone was removed from Kitchen frame. Pair again to continue."].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Shopping"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.buttons.allElementsBoundByIndex.map(\.label), ["Frame", "Climate"])
        XCTAssertTrue(app.buttons["Kitchen frame, Tap to pair"].waitForExistence(timeout: 5))
        snap("revoked")
    }

    func testPairingDecoyThenTryAgainWhileTheWindowIsClosedThenCancel() {
        let app = launch("pairing", ["-demoPairing", "failed"])
        XCTAssertTrue(app.staticTexts["The frame ended this pairing. Nothing was paired. Open Pair a phone on the frame and try again."].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertTrue(app.buttons["Close"].exists)
        app.buttons["Try again"].tap()
        let name = app.textFields["Maya's iPhone"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        app.buttons["Pair"].tap()
        XCTAssertTrue(app.staticTexts["The frame isn't ready to pair. On the frame, open Settings → Phone app → Pair a phone, then try again."].waitForExistence(timeout: 8))
        XCTAssertTrue(name.exists)
        XCTAssertTrue(app.buttons["Pair"].isEnabled)
        snap("pairing-window-closed")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        let frame = app.buttons["Kitchen frame, Tap to pair"]
        XCTAssertTrue(frame.waitForExistence(timeout: 5))
        frame.tap()
        XCTAssertTrue(app.textFields["Maya's iPhone"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cancel"].exists)
    }

    func testCodeTypedAfterATimedOutAttemptIsStillChecked() {
        for delay in [0.0, 0.6, 2.5] {
            let app = launch("pairing", ["-demoPairing", "expired"])
            XCTAssertTrue(app.staticTexts["Pairing timed out. Nothing was paired. Open Pair a phone on the frame and try again."].waitForExistence(timeout: 15))
            app.buttons["Try again"].tap()
            XCTAssertTrue(app.buttons["Pair"].waitForExistence(timeout: 5))
            app.buttons["Pair"].tap()
            let entry = app.textFields["Pairing code"]
            XCTAssertTrue(entry.waitForExistence(timeout: 10))
            if delay == 0 {
                entry.tap()
            } else {
                Thread.sleep(forTimeInterval: delay)
            }
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            entry.typeText("000000")
            let checked = app.staticTexts["That code didn't match. 2 tries left."].waitForExistence(timeout: 5)
            if !checked { snap("code-after-timeout-ignored-\(delay)") }
            XCTAssertTrue(checked, "six digits typed \(delay)s after a timed-out attempt must be checked; field value \(String(describing: entry.value))")
            entry.typeText("000000")
            XCTAssertTrue(app.staticTexts["That code didn't match. 1 try left."].waitForExistence(timeout: 5), "the same wrong code typed again is checked again")
            app.terminate()
        }
    }

    func testSixDigitsThatAreNeverCheckedGetACalmMessageAndTryAgain() {
        let app = launch("pairing", ["-demoPairing", "code", "-demoDropCode", "YES"])
        let entry = app.textFields["Pairing code"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        entry.typeText("000000")
        XCTAssertFalse(app.buttons["Try again"].exists)
        let calm = app.staticTexts["That code couldn't be checked. Tap Try again, or Cancel and start over."]
        XCTAssertTrue(calm.waitForExistence(timeout: 8), "a code that is not checked within a few seconds must say so")
        snap("code-unchecked")
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.staticTexts["That code didn't match. 2 tries left."].waitForExistence(timeout: 5), "Try again resubmits the held digits")
        XCTAssertFalse(calm.exists)
        XCTAssertFalse(app.buttons["Try again"].exists)
    }

    func testCancellingMidCodeAndBackgroundingKeepTheSheetConsistent() {
        let app = launch("pairing", ["-demoPairing", "code"])
        let entry = app.textFields["Pairing code"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You have three tries."].waitForExistence(timeout: 5))
        entry.typeText("000000")
        XCTAssertTrue(app.staticTexts["That code didn't match. 2 tries left."].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(entry.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Kitchen frame, Tap to pair"].waitForExistence(timeout: 5))
    }

    func testPastedWallOfTextIsClippedToTheFrameLimitAndEmojiStillAdds() {
        let app = launch("shopping")
        let field = app.textFields["Add an item"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        paste(String(repeating: "x", count: 500), into: field, in: app)
        XCTAssertEqual((field.value as? String)?.count, 80)
        field.typeText("\n")
        XCTAssertEqual(field.value as? String, "Add an item")
        XCTAssertTrue(app.buttons[String(repeating: "x", count: 80)].waitForExistence(timeout: 5))
        field.typeText("👨‍👩‍👧‍👦 trip\n")
        XCTAssertTrue(app.buttons["👨‍👩‍👧‍👦 trip"].waitForExistence(timeout: 5))
        snap("pasted-wall")
    }

    func testCalendarNameOverTheFrameLimitIsNotOffered() {
        let setup = launch("setup", ["-demoScroll", "calendarForm"])
        let name = setup.textFields["Family"]
        setup.reveal(name)
        paste(String(repeating: "📅", count: 40), into: name, in: setup)
        XCTAssertLessThanOrEqual((name.value as? String)?.unicodeScalars.count ?? 0, 60)
        let link = setup.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR placeholderValue == %@", "Secret address in iCal format", "Paste the secret address")).firstMatch
        setup.bringAboveKeyboard(link)
        link.tap()
        link.typeText("https://calendar.google.com/calendar/ical/x/private-abc/basic.ics")
        let addCalendar = setup.buttons["Add calendar"]
        setup.bringAboveKeyboard(addCalendar)
        XCTAssertFalse(addCalendar.isEnabled, "31+ emoji exceed the frame's UTF-16 limit and must not be offered")
        setup.bringAboveKeyboard(name)
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        XCTAssertEqual(name.value as? String, "Family", "forty deletes must clear the forty pasted emoji")
        name.typeText("Work")
        XCTAssertEqual(name.value as? String, "Work")
        setup.bringAboveKeyboard(addCalendar)
        XCTAssertTrue(addCalendar.isEnabled)
    }
}
