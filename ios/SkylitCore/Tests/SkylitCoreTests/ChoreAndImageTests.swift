import XCTest
@testable import SkylitCore

final class ChoreLogicTests: XCTestCase {
    private let denver = TimeZone(identifier: "America/Denver")!
    private let sunday = fixedDate("2026-10-11T18:00:00Z")

    func testWeekdayNumbersStartAtSunday() {
        XCTAssertEqual(ChoreLogic.weekday(sunday, timeZone: denver), 0)
        XCTAssertEqual(ChoreLogic.weekday(fixedDate("2026-10-12T18:00:00Z"), timeZone: denver), 1)
        XCTAssertEqual(ChoreLogic.weekday(fixedDate("2026-10-17T18:00:00Z"), timeZone: denver), 6)
    }

    func testDateUsesFrameTimezoneNotUTC() {
        let lateEvening = fixedDate("2026-10-12T03:30:00Z")
        XCTAssertEqual(ChoreLogic.dateString(lateEvening, timeZone: denver), "2026-10-11")
        XCTAssertEqual(ChoreLogic.dateString(lateEvening, timeZone: TimeZone(identifier: "UTC")!), "2026-10-12")
        XCTAssertEqual(ChoreLogic.weekday(lateEvening, timeZone: denver), 0)
        XCTAssertEqual(ChoreLogic.dateString(fixedDate("2026-01-05T12:00:00Z"), timeZone: denver), "2026-01-05")
    }

    func testEmptyDaysMeansEveryDay() {
        let daily = Chore(id: "c", title: "Daily")
        for day in 0...6 { XCTAssertTrue(ChoreLogic.isDue(daily, weekday: day)) }
        let weekdays = Chore(id: "c", title: "School", days: [1, 2, 3, 4, 5])
        XCTAssertFalse(ChoreLogic.isDue(weekdays, weekday: 0))
        XCTAssertTrue(ChoreLogic.isDue(weekdays, weekday: 1))
        XCTAssertFalse(ChoreLogic.isDue(weekdays, weekday: 6))
        XCTAssertTrue(ChoreLogic.isDue(Chore(id: "c", title: "Sun", days: [0]), weekday: 0))
    }

    func testTodayGroupsByPersonWithProgress() {
        let state = FrameState(
            rev: 1,
            people: [Person(id: "p1", name: "Maya", color: "#00A36C"), Person(id: "p2", name: "Leo", color: "#112233"), Person(id: "p3", name: "Idle", color: "#445566")],
            chores: [
                Chore(id: "c1", title: "Bed", personId: "p1", done: ["2026-10-11"]),
                Chore(id: "c2", title: "Cat", personId: "p1", done: ["2026-10-10"]),
                Chore(id: "c3", title: "School bag", personId: "p2", days: [1, 2, 3, 4, 5]),
                Chore(id: "c4", title: "Plants", personId: "p2", days: [0], done: ["2026-10-11"]),
                Chore(id: "c5", title: "Recycling", personId: nil),
                Chore(id: "c6", title: "Orphan", personId: "gone"),
            ],
            settings: FrameSettings(location: FrameLocation(name: "Denver", latitude: 39.74, longitude: -104.99, timezone: "America/Denver")))
        let today = ChoreLogic.today(state, now: sunday)
        XCTAssertEqual(today.date, "2026-10-11")
        XCTAssertEqual(today.groups.map(\.id), ["p1", "p2", "anyone"])
        XCTAssertEqual(today.groups[0].chores.map(\.isDone), [true, false])
        XCTAssertEqual(today.groups[1].chores.map(\.chore.id), ["c4"])
        XCTAssertEqual(today.groups[2].chores.map(\.chore.id), ["c5", "c6"])
        XCTAssertNil(today.groups[2].person)
        XCTAssertEqual(today.total, 5)
        XCTAssertEqual(today.doneCount, 2)
        XCTAssertEqual(today.progress, 0.4, accuracy: 0.0001)
        XCTAssertEqual(today.groups[0].doneCount, 1)
    }

    func testNoChoresMeansZeroProgress() {
        let today = ChoreLogic.today(FrameState(rev: 1), now: sunday)
        XCTAssertTrue(today.groups.isEmpty)
        XCTAssertEqual(today.total, 0)
        XCTAssertEqual(today.progress, 0)
    }

    func testTimezoneFallsBackToDeviceWhenMissingOrInvalid() {
        XCTAssertEqual(ChoreLogic.timeZone(for: FrameState(rev: 1)), .current)
        let odd = FrameState(rev: 1, settings: FrameSettings(location: FrameLocation(name: "X", latitude: 0, longitude: 0, timezone: "Not/AZone")))
        XCTAssertEqual(ChoreLogic.timeZone(for: odd), .current)
    }

    func testDaysSummary() {
        XCTAssertEqual(ChoreLogic.daysSummary([]), "Every day")
        XCTAssertEqual(ChoreLogic.daysSummary([0, 1, 2, 3, 4, 5, 6]), "Every day")
        XCTAssertEqual(ChoreLogic.daysSummary([5, 4, 3, 2, 1]), "Weekdays")
        XCTAssertEqual(ChoreLogic.daysSummary([6, 0]), "Weekends")
        XCTAssertEqual(ChoreLogic.daysSummary([3, 1]), "Mon, Wed")
        XCTAssertEqual(ChoreLogic.daysSummary([9]), "Every day")
    }
}

final class ImagePreparationTests: XCTestCase {
    func testLargeLandscapeIsDownscaledToJPEG() throws {
        let jpeg = try ImagePreparation.jpeg(from: makeImage(width: 4000, height: 3000))
        XCTAssertEqual(Array(jpeg.prefix(3)), [0xFF, 0xD8, 0xFF])
        let size = try XCTUnwrap(ImagePreparation.pixelSize(of: jpeg))
        XCTAssertEqual(size.width, 2560)
        XCTAssertEqual(size.height, 1920)
        XCTAssertLessThanOrEqual(jpeg.count, Limits.photoBytes)
    }

    func testPortraitUsesLongestEdge() throws {
        let jpeg = try ImagePreparation.jpeg(from: makeImage(width: 1500, height: 5000))
        let size = try XCTUnwrap(ImagePreparation.pixelSize(of: jpeg))
        XCTAssertEqual(size.height, 2560)
        XCTAssertEqual(size.width, 768)
    }

    func testSmallImageIsNotUpscaled() throws {
        let jpeg = try ImagePreparation.jpeg(from: makeImage(width: 800, height: 600, type: "public.jpeg"))
        let size = try XCTUnwrap(ImagePreparation.pixelSize(of: jpeg))
        XCTAssertEqual(size.width, 800)
        XCTAssertEqual(size.height, 600)
    }

    func testSizeBudgetForcesSmallerOutput() throws {
        let source = makeImage(width: 3000, height: 2000)
        let roomy = try ImagePreparation.jpeg(from: source)
        let budget = roomy.count / 3
        let tight = try ImagePreparation.jpeg(from: source, maxBytes: budget)
        XCTAssertLessThanOrEqual(tight.count, budget)
        XCTAssertEqual(Array(tight.prefix(2)), [0xFF, 0xD8])
    }

    func testImpossibleBudgetThrows() {
        XCTAssertThrowsError(try ImagePreparation.jpeg(from: makeImage(width: 2000, height: 2000), maxBytes: 64)) {
            XCTAssertEqual($0 as? ImagePreparationError, .tooLarge)
        }
    }

    func testGarbageThrowsUnreadable() {
        XCTAssertThrowsError(try ImagePreparation.jpeg(from: Data("not an image".utf8))) {
            XCTAssertEqual($0 as? ImagePreparationError, .unreadable)
        }
        XCTAssertThrowsError(try ImagePreparation.jpeg(from: Data())) {
            XCTAssertEqual($0 as? ImagePreparationError, .unreadable)
        }
    }

    func testImagesBelowTheFrameMinimumAreRejectedLocally() {
        XCTAssertThrowsError(try ImagePreparation.jpeg(from: makeImage(width: 300, height: 300))) {
            XCTAssertEqual($0 as? ImagePreparationError, .tooSmall)
        }
        XCTAssertThrowsError(try ImagePreparation.jpeg(from: makeImage(width: 400, height: 200))) {
            XCTAssertEqual($0 as? ImagePreparationError, .tooSmall)
        }
        XCTAssertNoThrow(try ImagePreparation.jpeg(from: makeImage(width: 320, height: 240)))
        XCTAssertNoThrow(try ImagePreparation.jpeg(from: makeImage(width: 240, height: 320)))
    }

    func testExifOrientationIsBakedIntoPixels() throws {
        let sideways = makeMarkedImage(width: 800, height: 600, type: "public.jpeg", orientation: 6)
        XCTAssertEqual(orientation(of: sideways), 6)
        let jpeg = try ImagePreparation.jpeg(from: sideways)
        let size = try XCTUnwrap(ImagePreparation.pixelSize(of: jpeg))
        XCTAssertEqual(size.width, 600)
        XCTAssertEqual(size.height, 800)
        XCTAssertTrue([nil, 1].contains(orientation(of: jpeg)))
        let corners = try XCTUnwrap(cornerColors(of: jpeg))
        XCTAssertTrue(corners.topRight.isRed, "the stored top-left marker must end up top-right once rotated upright")
        XCTAssertFalse(corners.topLeft.isRed)
        XCTAssertFalse(corners.bottomLeft.isRed)
        XCTAssertFalse(corners.bottomRight.isRed)
    }

    func testUprightImageKeepsItsMarkerInPlace() throws {
        let jpeg = try ImagePreparation.jpeg(from: makeMarkedImage(width: 800, height: 600, type: "public.jpeg", orientation: 1))
        let corners = try XCTUnwrap(cornerColors(of: jpeg))
        XCTAssertTrue(corners.topLeft.isRed)
        XCTAssertFalse(corners.topRight.isRed)
    }

    func testHEICIsConvertedToUprightJPEG() throws {
        let heic = makeMarkedImage(width: 800, height: 600, type: "public.heic", orientation: 6)
        try XCTSkipIf(heic.isEmpty, "This machine cannot encode HEIC")
        let jpeg = try ImagePreparation.jpeg(from: heic)
        XCTAssertEqual(Array(jpeg.prefix(3)), [0xFF, 0xD8, 0xFF])
        let size = try XCTUnwrap(ImagePreparation.pixelSize(of: jpeg))
        XCTAssertEqual(size.width, 600)
        XCTAssertEqual(size.height, 800)
        XCTAssertTrue([nil, 1].contains(orientation(of: jpeg)))
        XCTAssertEqual(try XCTUnwrap(cornerColors(of: jpeg)).topRight.isRed, true)
    }

    func testThumbnail() {
        let thumbnail = ImagePreparation.thumbnail(from: makeImage(width: 1200, height: 600), maxEdge: 300)
        XCTAssertEqual(thumbnail?.width, 300)
        XCTAssertEqual(thumbnail?.height, 150)
    }
}

final class PaletteTests: XCTestCase {
    func testEveryPaletteHasNineValidTokensPerMode() {
        XCTAssertEqual(Palettes.all.map(\.id), ["linen", "sage", "stone", "ocean", "plum", "contrast"])
        for palette in Palettes.all {
            XCTAssertEqual(palette.light.count, 9)
            XCTAssertEqual(palette.dark.count, 9)
            XCTAssertTrue((palette.light + palette.dark).allSatisfy(Limits.isHexColor))
        }
        XCTAssertTrue(Palettes.swatches.allSatisfy(Limits.isHexColor))
    }

    func testTokensFollowAppearanceJsKeyOrder() {
        let linen = Palettes.palette("linen").tokens(dark: false)
        XCTAssertEqual(linen.bg, "#eee8dd")
        XCTAssertEqual(linen.panel, "#faf7f0")
        XCTAssertEqual(linen.ink, "#352e28")
        XCTAssertEqual(linen.accent, "#9a513b")
        XCTAssertEqual(linen.accentInk, "#fff9f0")
        XCTAssertEqual(linen.soft, "#ead0b5")
        XCTAssertEqual(Palettes.palette("ocean").tokens(dark: true).accent, "#95c1d1")
    }

    func testUnknownPaletteFallsBackToLinenAndModesResolve() {
        XCTAssertEqual(Palettes.palette("cocoa").id, "linen")
        XCTAssertTrue(Palettes.isDark(mode: "dark", systemDark: false))
        XCTAssertFalse(Palettes.isDark(mode: "light", systemDark: true))
        XCTAssertTrue(Palettes.isDark(mode: "auto", systemDark: true))
        XCTAssertFalse(Palettes.isDark(mode: "auto", systemDark: false))
    }

    func testPalettesMatchTheDashboardSource() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../web/appearance.js").standardizedFileURL
        guard let script = try? String(contentsOf: source, encoding: .utf8) else {
            throw XCTSkip("web/appearance.js is not next to this checkout")
        }
        for palette in Palettes.all {
            let light = palette.light.map { "'\($0)'" }.joined(separator: ",")
            let dark = palette.dark.map { "'\($0)'" }.joined(separator: ",")
            XCTAssertTrue(script.contains("\(palette.id):{name:'\(palette.name)',light:[\(light)],dark:[\(dark)]}"), palette.id)
        }
    }
}
