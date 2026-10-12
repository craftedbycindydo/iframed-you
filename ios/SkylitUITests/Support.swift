import XCTest

extension XCUIApplication {
    var keyboardTop: CGFloat {
        let keyboard = keyboards.firstMatch
        return keyboard.exists ? keyboard.frame.minY : frame.maxY
    }

    var headerBottom: CGFloat {
        let title = staticTexts.matching(NSPredicate(format: "label IN %@", ["Shopping", "Chores", "Frame", "Climate", "Photos", "iFramed You"])).firstMatch
        return title.exists ? title.frame.maxY + 44 : 0
    }

    func isAboveKeyboard(_ element: XCUIElement, below top: CGFloat? = nil) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        return frame.maxY <= keyboardTop && frame.minY >= (top ?? headerBottom) && element.isHittable
    }

    func bringAboveKeyboard(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let list = collectionViews.firstMatch
        let top = headerBottom
        for step in 0..<10 where !isAboveKeyboard(element, below: top) {
            let direction: CGFloat = step < 7 ? -1 : 1
            let from = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            let to = from.withOffset(CGVector(dx: 0, dy: direction * 140))
            from.press(forDuration: 0.05, thenDragTo: to)
            Thread.sleep(forTimeInterval: 0.4)
        }
        if !isAboveKeyboard(element, below: top), let dir = ProcessInfo.processInfo.environment["SKYLIT_SHOTS"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("not-above-keyboard-\(line).png"))
        }
        XCTAssertTrue(isAboveKeyboard(element, below: top), "\(element) never came above the keyboard; keyboard top \(keyboardTop) header bottom \(top) frame \(element.frame)", file: file, line: line)
    }

    func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 5)
        let list = collectionViews.firstMatch
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            list.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) never became visible", file: file, line: line)
    }

    func dismissKeyboardIfShown(file: StaticString = #filePath, line: UInt = #line) {
        let keyboard = keyboards.firstMatch
        guard keyboard.exists else { return }
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).press(forDuration: 0.1, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        if keyboard.waitForNonExistence(timeout: 2) { return }
        swipeDown()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 3), "the keyboard stayed up", file: file, line: line)
    }
}
