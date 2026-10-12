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

    func isAboveKeyboard(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 1), element.isHittable else { return false }
        let frame = element.frame
        return frame.maxY <= keyboardTop && frame.minY >= headerBottom
    }

    func bringAboveKeyboard(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let list = collectionViews.firstMatch
        for step in 0..<12 where !isAboveKeyboard(element) {
            let direction: CGFloat = step < 8 ? -1 : 1
            let from = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            let to = from.withOffset(CGVector(dx: 0, dy: direction * 140))
            from.press(forDuration: 0.05, thenDragTo: to)
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(isAboveKeyboard(element), "\(element) never came above the keyboard", file: file, line: line)
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
