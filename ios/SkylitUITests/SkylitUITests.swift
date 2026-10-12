import XCTest

private enum Size {
    static let touch: CGFloat = 44
}

final class SkylitUITests: XCTestCase {
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

    private func tabLabels(_ app: XCUIApplication) -> [String] {
        app.tabBars.buttons.allElementsBoundByIndex.map(\.label)
    }

    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) == true
    }

    private func element(labelled label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SKYLIT_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testTabsAreShoppingPhotosChoresClimateFrame() {
        let app = launch("shopping")
        XCTAssertTrue(app.tabBars.buttons["Shopping"].waitForExistence(timeout: 10))
        XCTAssertEqual(tabLabels(app), ["Shopping", "Photos", "Chores", "Climate", "Frame"])
    }

    func testClimateIsReachableWithoutAFrame() {
        let app = launch("connect")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(tabLabels(app), ["Frame", "Climate"])
        app.tabBars.buttons["Climate"].tap()
        XCTAssertTrue(app.staticTexts["Climate"].waitForExistence(timeout: 5))
    }

    func testReturnAddsTheItemKeepsFocusAndShowsNoFloatingDone() {
        let app = launch("shopping")
        let field = app.textFields["Add an item"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(hasKeyboardFocus(field))
        XCTAssertFalse(app.buttons["Done"].exists)
        field.typeText("Eggs")
        snap("shopping-keyboard-typing")
        field.typeText("\n")
        XCTAssertTrue(app.buttons["Eggs"].waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Add an item")
        XCTAssertTrue(hasKeyboardFocus(field))
        XCTAssertFalse(app.buttons["Done"].exists)
        snap("shopping-keyboard-added")
    }

    func testScaledGlyphsDoNotOverlapTextAtTheLargestDynamicType() {
        let app = launch("shopping", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let field = app.textFields["Add an item"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let milk = app.buttons["Oranges, 6"]
        XCTAssertTrue(milk.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(field.frame.height, Size.touch)
        XCTAssertFalse(field.frame.intersects(milk.frame))
        snap("ax5-shopping")
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 5) { snap("ax5-no-keyboard") }
        XCTAssertTrue(app.keyboards.firstMatch.exists, "tapping the add field \(field.frame) at the largest type size must bring up the keyboard; milk row \(milk.frame)")
        field.typeText("Eggs")
        XCTAssertEqual(field.value as? String, "Eggs")
        let tick = app.buttons["Add an item"]
        XCTAssertTrue(tick.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(tick.frame.width, Size.touch)
        XCTAssertGreaterThanOrEqual(tick.frame.height, Size.touch)
        XCTAssertLessThanOrEqual(field.frame.maxX, tick.frame.minX)
        XCTAssertFalse(field.frame.intersects(tick.frame))
        XCTAssertTrue(tick.isHittable)
        snap("ax5-shopping-typing")
        tick.tap()
        XCTAssertTrue(app.buttons["Eggs"].waitForExistence(timeout: 5))
    }

    func testOnlyOneShoppingEditorIsOpenAtATime() {
        let app = launch("shopping")
        let milk = app.buttons["Milk, 2"]
        XCTAssertTrue(milk.waitForExistence(timeout: 5))
        milk.swipeRight()
        app.buttons["Edit"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Finish editing"].waitForExistence(timeout: 5))
        let oranges = app.buttons["Oranges, 6"]
        oranges.swipeRight()
        app.buttons["Edit"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Finish editing"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Finish editing").count, 1)
    }

    func testPairingTimeoutIsCalmAndOffersTryAgainInTheSheet() {
        let app = launch("pairing", ["-demoPairing", "expired"])
        let calm = element(labelled: "Pairing timed out. Nothing was paired. Open Pair a phone on the frame and try again.", in: app)
        XCTAssertTrue(calm.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Another device")).firstMatch.exists)
        snap("pairing-timeout")
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.textFields["Maya's iPhone"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Pair"].exists)
    }

    func testCalendarFormKeepsWhatYouTypedWhenTheFrameRefusesIt() {
        let app = launch("setup", ["-demoScroll", "calendarForm"])
        let name = app.textFields["Family"]
        app.reveal(name)
        name.tap()
        name.typeText("Work")
        let link = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR placeholderValue == %@", "Secret address in iCal format", "Paste the secret address")).firstMatch
        app.bringAboveKeyboard(link)
        link.tap()
        link.typeText("https://example.com/not-a-calendar")
        let addCalendar = app.buttons["Add calendar"]
        app.bringAboveKeyboard(addCalendar)
        addCalendar.tap()
        XCTAssertTrue(app.staticTexts["The frame didn't accept that. Check what you entered."].waitForExistence(timeout: 8))
        snap("notice-toast-over-tabbar")
        app.bringAboveKeyboard(name)
        XCTAssertEqual(name.value as? String, "Work")
        app.bringAboveKeyboard(link)
        XCTAssertEqual(link.value as? String, "https://example.com/not-a-calendar")
    }

    func testChoreEditorOpensOnceAndClosesWithTheTick() {
        let app = launch("chores", ["-demoScroll", "all"])
        let chore = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Make bed")).firstMatch
        XCTAssertTrue(chore.waitForExistence(timeout: 5))
        chore.tap()
        XCTAssertTrue(app.buttons["Finish editing"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Feed Momo")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Finish editing"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Finish editing").count, 1)
        app.buttons["Finish editing"].tap()
        XCTAssertFalse(app.buttons["Finish editing"].waitForExistence(timeout: 2))
    }
}
