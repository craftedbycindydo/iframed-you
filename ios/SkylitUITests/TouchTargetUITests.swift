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
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launch()
        return app
    }

    private func undersized(in app: XCUIApplication) -> [String] {
        guard let tree = try? app.snapshot() else { return ["could not snapshot the screen"] }
        let window = app.windows.firstMatch.frame
        let containers = [app.tabBars.firstMatch, app.navigationBars.firstMatch, app.keyboards.firstMatch,
                          app.segmentedControls.firstMatch, app.steppers.firstMatch].filter(\.exists).map(\.frame)
        var found: [String] = []
        func visit(_ node: any XCUIElementSnapshot) {
            let frame = node.frame
            if Self.types.contains(node.elementType), frame.width > 0, frame.width < Self.minimum || frame.height < Self.minimum,
               window.contains(frame), !containers.contains(where: { $0.intersects(frame) }) {
                let name = node.label.isEmpty ? node.identifier : node.label
                if !name.isEmpty, !Self.rowFocused.contains(name),
                   app.descendants(matching: node.elementType).matching(NSPredicate(format: "label == %@ OR identifier == %@", name, name)).firstMatch.isHittable {
                    found.append("\(name) [\(node.elementType.rawValue)] \(Int(frame.width))×\(Int(frame.height))")
                }
            }
            node.children.forEach(visit)
        }
        visit(tree)
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
        XCTAssertTrue(app.buttons["Clear 2 Completed"].waitForExistence(timeout: 5), "bottom edge of Clear completed \(clear.frame) must open the dialog, not tick the row below")
        dismissDialog(app)
        XCTAssertEqual(app.buttons["Oat cereal"].value as? String, "In the basket")
        let add = app.textFields["Add an item"]
        add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(hasKeyboardFocus(add), "top edge of \(add.frame) must focus the field")
        add.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let milk = app.buttons["Milk, 2"]
        XCTAssertTrue(milk.waitForExistence(timeout: 5))
        let between = CGPoint(x: milk.frame.midX, y: (add.frame.maxY + milk.frame.minY) / 2)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: between.x, dy: between.y)).tap()
        XCTAssertEqual(milk.value as? String, "To buy", "a tap between the add field \(add.frame) and the first row \(milk.frame) must not tick the row")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
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
        app.reveal(app.textFields["Family"])
        assertTargets(app, "setup calendar form")
        let link = app.textFields["Secret address in iCal format"]
        app.textFields["Family"].tap()
        link.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
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
