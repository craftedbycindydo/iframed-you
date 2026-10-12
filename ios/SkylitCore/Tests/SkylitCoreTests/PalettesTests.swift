import XCTest
@testable import SkylitCore

final class PalettesTests: XCTestCase {
    func testEverySwatchHasASpokenName() {
        XCTAssertEqual(Palettes.swatchNames.count, Palettes.swatches.count)
        XCTAssertEqual(Set(Palettes.swatchNames).count, Palettes.swatches.count)
        for hex in Palettes.swatches {
            XCTAssertFalse(Palettes.swatchName(hex).hasPrefix("#"), hex)
        }
        XCTAssertEqual(Palettes.swatchName("#2d5bff"), "Cobalt")
        XCTAssertEqual(Palettes.swatchName("#123456"), "#123456")
    }

    func testSixPalettesWithLightAndDarkTokens() {
        XCTAssertEqual(Palettes.all.count, 6)
        for palette in Palettes.all {
            XCTAssertEqual(palette.light.count, 9, palette.id)
            XCTAssertEqual(palette.dark.count, 9, palette.id)
        }
    }
}
