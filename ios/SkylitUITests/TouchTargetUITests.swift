import XCTest

final class TouchTargetUITests: XCTestCase {
    private static let minimum: CGFloat = 43
    private static let rowFocused: Set<String> = ["Secret address in iCal format", "Album link", "Paste"]
    private static let types: [XCUIElement.ElementType] = [.button, .textField, .secureTextField, .switch, .menuButton, .link]

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ screen: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoFrame", "YES", "-demoScreen", screen] + extra
        app.launch()
        return app
    }

    private func isSystemControl(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let frame = element.frame
        let containers = [app.tabBars.firstMatch, app.navigationBars.firstMatch, app.keyboards.firstMatch,
                          app.segmentedControls.firstMatch, app.steppers.firstMatch]
        return containers.contains { $0.exists && $0.frame.intersects(frame) }
    }

    private func undersized(in app: XCUIApplication) -> [String] {
        let screen = XCUIScreen.main.screenshot().image.size
        var found: [String] = []
        for type in Self.types {
            for element in app.descendants(matching: type).allElementsBoundByIndex where element.isHittable {
                let frame = element.frame
                guard frame.minY >= 0, frame.maxY <= screen.height, frame.width > 0, !isSystemControl(element, in: app) else { continue }
                let name = element.label.isEmpty ? element.identifier : element.label
                guard !Self.rowFocused.contains(name) else { continue }
                if frame.width < Self.minimum || frame.height < Self.minimum {
                    found.append("\(name) [\(type.rawValue)] \(Int(frame.width))×\(Int(frame.height))")
                }
            }
        }
        return found
    }

    private func assertTargets(_ app: XCUIApplication, _ context: String) {
        let bad = undersized(in: app)
        XCTAssertTrue(bad.isEmpty, "\(context): under 44 pt: \(bad.joined(separator: "; "))")
    }

    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) == true
    }

    private func dismissDialog(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
    }

    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SKYLIT_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testShoppingTargetsAndEdgeTapsLand() {
        let app = launch("shopping")
        let clear = app.buttons["Clear completed"]
        XCTAssertTrue(clear.waitForExistence(timeout: 8))
        assertTargets(app, "shopping")
        clear.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(app.buttons["Clear 2 Completed"].waitForExistence(timeout: 5))
        dismissDialog(app)
        XCTAssertFalse(app.buttons["Clear 2 Completed"].waitForExistence(timeout: 2))
        clear.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
        XCTAssertTrue(app.buttons["Clear 2 Completed"].waitForExistence(timeout: 5))
        dismissDialog(app)
        let add = app.textFields["Add an item"]
        add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(hasKeyboardFocus(add))
        app.buttons["Milk, 2"].swipeRight()
        app.buttons["Edit"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Finish editing"].waitForExistence(timeout: 5))
        assertTargets(app, "shopping editor")
    }

    func testChoresTargetsAndDayCirclesAcceptEdgeTaps() {
        let app = launch("chores", ["-demoScroll", "all"])
        let chore = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Make bed")).firstMatch
        XCTAssertTrue(chore.waitForExistence(timeout: 8))
        chore.tap()
        XCTAssertTrue(app.buttons["Finish editing"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists, "opening a chore editor must not cover it with a keyboard")
        assertTargets(app, "chore editor")
        snap("tt-chore-editor")
        let wednesday = app.buttons["Wed"]
        XCTAssertTrue(wednesday.waitForExistence(timeout: 3))
        let wasOn = wednesday.isSelected
        wednesday.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(wednesday.waitForExistence(timeout: 3))
        XCTAssertNotEqual(wednesday.isSelected, wasOn)
        wednesday.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
        XCTAssertEqual(wednesday.isSelected, wasOn)
        app.buttons["Finish editing"].tap()
        app.buttons["People"].tap()
        XCTAssertTrue(app.navigationBars["People"].waitForExistence(timeout: 5))
        assertTargets(app, "people")
        app.buttons["Add person"].tap()
        XCTAssertTrue(app.navigationBars["New Person"].waitForExistence(timeout: 5))
        assertTargets(app, "person editor")
    }

    func testSetupTargets() {
        let app = launch("setup", ["-demoScroll", "calendarForm"])
        XCTAssertTrue(app.textFields["Family"].waitForExistence(timeout: 8))
        assertTargets(app, "setup calendar form")
        let link = app.textFields["Secret address in iCal format"]
        app.textFields["Family"].tap()
        link.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
        XCTAssertTrue(hasKeyboardFocus(link))
        snap("tt-calendar-form")
        app.swipeDown()
        app.swipeDown()
        assertTargets(app, "setup top")
    }

    func testPhotosConnectPairingAndClimateTargets() {
        var app = launch("photos")
        XCTAssertTrue(app.buttons["Add photos"].waitForExistence(timeout: 8))
        assertTargets(app, "photos")
        app = launch("connect")
        let frame = app.buttons["Kitchen frame, Tap to pair"]
        XCTAssertTrue(frame.waitForExistence(timeout: 8))
        assertTargets(app, "connect")
        frame.tap()
        XCTAssertTrue(app.buttons["Pair"].waitForExistence(timeout: 8))
        assertTargets(app, "pairing sheet")
        app = launch("climate", ["-demoClimate", "many"])
        XCTAssertTrue(app.buttons["Level-0 settings"].waitForExistence(timeout: 8))
        assertTargets(app, "climate")
        snap("tt-climate")
        app = launch("climate", ["-demoClimate", "signedOut"])
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 8))
        assertTargets(app, "climate sign-in")
    }
}
