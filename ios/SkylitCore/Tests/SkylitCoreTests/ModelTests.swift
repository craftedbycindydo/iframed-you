import XCTest
@testable import SkylitCore

final class ModelTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testInfo() throws {
        let info = try decode(FrameInfo.self, ##"{"v":2,"frameId":"f-1","name":"Kitchen","pairing":true,"extra":true}"##)
        XCTAssertEqual(info, FrameInfo(v: 2, frameId: "f-1", name: "Kitchen", pairing: true))
        XCTAssertFalse(try decode(FrameInfo.self, ##"{"v":2,"frameId":"f-1","name":"Kitchen"}"##).pairing)
    }

    func testPairResultCarriesNoToken() throws {
        let result = try decode(PairResult.self, ##"{"deviceId":"d4","frameId":"f-1","name":"Kitchen","token":"ignored"}"##)
        XCTAssertEqual(result, PairResult(deviceId: "d4", frameId: "f-1", name: "Kitchen"))
    }

    func testServerSuppliedNamesAreClampedAndStripped() throws {
        let long = String(repeating: "n", count: 500)
        XCTAssertEqual(try decode(FrameInfo.self, ##"{"v":2,"frameId":"f","name":"\##(long)"}"##).name.count, 80)
        let spoofed = try decode(FrameInfo.self, ##"{"v":2,"frameId":"f","name":"Kitchen\u202E\u0007\n frame "}"##)
        XCTAssertEqual(spoofed.name, "Kitchen frame")
        let device = try decode(PairedDevice.self, ##"{"id":"d1","name":"\##(long)","pairedAt":"x"}"##)
        XCTAssertEqual(device.name.count, 40)
        XCTAssertFalse(device.isSelf)
        XCTAssertNil(device.lastSeenDate)
        XCTAssertEqual(DiscoveredFrame(frameId: "f", name: long).name.count, 80)
        let album = try decode(ICloudAlbum.self, ##"{"name":"\##(long)","error":"\##(long)"}"##)
        XCTAssertEqual(album.name.count, 80)
        XCTAssertEqual(album.error?.count, 200)
    }

    func testDeviceNameRules() {
        XCTAssertEqual(Limits.cleanDeviceName("  Maya's iPhone \n"), "Maya's iPhone")
        XCTAssertEqual(Limits.cleanDeviceName(String(repeating: "n", count: 40))?.count, 40)
        XCTAssertEqual(Limits.cleanDeviceName("Maya 👩‍👧 phone"), "Maya 👩‍👧 phone")
        for refused in ["", "   ", String(repeating: "n", count: 41), "Maya\u{202E}enohPi", "Tab\there", "Bell\u{7}", "Mark\u{200F}"] {
            XCTAssertNil(Limits.cleanDeviceName(refused), refused.debugDescription)
        }
    }

    func testDevicesWithBothTimestampShapes() throws {
        let devices = try decode([PairedDevice].self, """
            [{"id":"d1","name":"Maya's iPhone","pairedAt":"2026-10-11T19:26:00Z","lastSeen":"2026-10-11T19:30:00Z","self":true},
             {"id":"d2","name":"Tablet","pairedAt":"2026-10-11T19:26:00.123+00:00"},
             {"id":"d3","name":"Odd","pairedAt":"yesterday"},
             {"id":"d4","name":"Unset clock","pairedAt":null,"lastSeen":null,"self":false}]
            """)
        XCTAssertEqual(devices.map(\.id), ["d1", "d2", "d3", "d4"])
        XCTAssertNotNil(devices[0].pairedDate)
        XCTAssertNotNil(devices[1].pairedDate)
        XCTAssertNil(devices[2].pairedDate)
        XCTAssertNil(devices[3].pairedDate)
        XCTAssertNil(devices[3].lastSeenDate)
    }

    func testContractStateExample() throws {
        let state = try decode(FrameState.self, """
            {"rev": 42,
             "people": [{"id":"p1","name":"Maya","color":"#00A36C"}],
             "chores": [{"id":"c1","title":"Make bed","emoji":"🛏️","personId":"p1","days":[1,2,3,4,5],"done":["2026-10-11"]}],
             "shopping": [{"id":"s1","name":"Milk","qty":2,"note":"","done":false}],
             "settings": {"location": {"name":"Denver","latitude":39.74,"longitude":-104.99,"timezone":"America/Denver"},
                          "appearance": {"palette":"linen","mode":"auto"}},
             "calendars": [{"id":"k1","name":"Family","color":"#2D5BFF"}],
             "photos": {"count": 12}}
            """)
        XCTAssertEqual(state.rev, 42)
        XCTAssertEqual(state.people, [Person(id: "p1", name: "Maya", color: "#00A36C")])
        XCTAssertEqual(state.chores, [Chore(id: "c1", title: "Make bed", emoji: "🛏️", personId: "p1", days: [1, 2, 3, 4, 5], done: ["2026-10-11"])])
        XCTAssertEqual(state.shopping, [ShoppingItem(id: "s1", name: "Milk", qty: 2, note: "", done: false)])
        XCTAssertEqual(state.settings.location, FrameLocation(name: "Denver", latitude: 39.74, longitude: -104.99, timezone: "America/Denver"))
        XCTAssertEqual(state.settings.appearance, FrameAppearance(palette: "linen", mode: "auto"))
        XCTAssertEqual(state.calendars, [CalendarFeed(id: "k1", name: "Family", color: "#2D5BFF")])
        XCTAssertEqual(state.photos.count, 12)
    }

    func testStateWithNullsAndUnknownFields() throws {
        let state = try decode(FrameState.self, """
            {"rev": 1, "future": {"x": 1},
             "people": [],
             "chores": [{"id":"c1","title":"Anyone","emoji":null,"personId":null,"days":[],"done":[],"streak":3}],
             "shopping": [{"id":"s1","name":"Eggs","qty":null,"note":null,"done":false,"aisle":"dairy"}],
             "settings": {"location": null, "appearance": {"palette":"ocean","mode":"dark","scale":"large"}},
             "calendars": [],
             "photos": {"count": 0, "bytes": 0}}
            """)
        XCTAssertNil(state.settings.location)
        XCTAssertNil(state.chores[0].personId)
        XCTAssertEqual(state.chores[0].emoji, "")
        XCTAssertEqual(state.chores[0].days, [])
        XCTAssertEqual(state.shopping[0].qty, 1)
        XCTAssertEqual(state.shopping[0].note, "")
        XCTAssertEqual(state.settings.appearance.palette, "ocean")
    }

    func testStateWithMissingSections() throws {
        let state = try decode(FrameState.self, ##"{"rev":7}"##)
        XCTAssertEqual(state, FrameState(rev: 7, settings: FrameSettings(supportsICloudAlbum: false)))
        XCTAssertEqual(state.settings.appearance, .standard)
    }

    func testStateWithoutRevIsRejected() {
        XCTAssertThrowsError(try decode(FrameState.self, ##"{"people":[]}"##))
    }

    func testChoreWithOmittedOptionalKeys() throws {
        let chore = try decode(Chore.self, ##"{"id":"c9","title":"Sweep"}"##)
        XCTAssertEqual(chore, Chore(id: "c9", title: "Sweep"))
    }

    func testLocationWithoutTimezone() throws {
        let location = try decode(FrameLocation.self, ##"{"name":"Pune","latitude":18.52,"longitude":73.86}"##)
        XCTAssertNil(location.timezone)
    }

    func testMutationResultForEveryObjectKey() throws {
        XCTAssertEqual(try decode(MutationResult.self, ##"{"rev":5,"person":{"id":"p2","name":"Leo","color":"#112233"}}"##).person?.name, "Leo")
        XCTAssertEqual(try decode(MutationResult.self, ##"{"rev":5,"chore":{"id":"c2","title":"Dishes","personId":null}}"##).chore?.title, "Dishes")
        XCTAssertEqual(try decode(MutationResult.self, ##"{"rev":5,"item":{"id":"s2","name":"Tea","qty":3,"note":"green","done":true}}"##).item?.qty, 3)
        XCTAssertEqual(try decode(MutationResult.self, ##"{"rev":5,"calendar":{"id":"k2","name":"School","color":"#445566"}}"##).calendar?.id, "k2")
        let photo = try decode(MutationResult.self, ##"{"rev":5,"photo":{"id":"abc","addedAt":"2026-10-11T10:00:00Z"}}"##)
        XCTAssertEqual(photo.photo, PhotoRef(id: "abc", addedAt: "2026-10-11T10:00:00Z"))
        XCTAssertEqual(photo.rev, 5)
        let bare = try decode(MutationResult.self, ##"{"rev":6}"##)
        XCTAssertEqual(bare, MutationResult(rev: 6))
    }

    func testPhotoList() throws {
        let photos = try decode([PhotoRef].self, ##"[{"id":"aa","addedAt":"2026-10-11T10:00:00Z"},{"id":"bb","addedAt":"2026-10-10T10:00:00Z"}]"##)
        XCTAssertEqual(photos.map(\.id), ["aa", "bb"])
    }

    func testStateEncodingRoundTrips() throws {
        let state = FrameState(rev: 3, people: [Person(id: "p1", name: "Maya", color: "#00A36C")],
                               chores: [Chore(id: "c1", title: "Bed", personId: nil, days: [0])],
                               shopping: [ShoppingItem(id: "s1", name: "Milk", qty: 2)],
                               settings: FrameSettings(location: nil, appearance: FrameAppearance(palette: "sage", mode: "dark")),
                               calendars: [CalendarFeed(id: "k1", name: "Family", color: "#2D5BFF")], photos: PhotoSummary(count: 4))
        let decoded = try JSONDecoder().decode(FrameState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
    }

    func testLimits() {
        XCTAssertEqual(Limits.cleanName("  Milk \n"), "Milk")
        XCTAssertNil(Limits.cleanName("   "))
        XCTAssertNil(Limits.cleanName(String(repeating: "a", count: 81)))
        XCTAssertNotNil(Limits.cleanName(String(repeating: "a", count: 80)))
        let flags = String(repeating: "🇨🇦", count: 40)
        XCTAssertEqual(flags.count, 40)
        XCTAssertNotNil(Limits.cleanName(flags))
        XCTAssertNil(Limits.cleanName(flags + "🇨🇦"))
        XCTAssertEqual(Limits.clipped(flags + "x", to: 80), flags)
        XCTAssertEqual(Limits.clipped("abc", to: 5), "abc")
        XCTAssertEqual(Limits.display(String(repeating: "🇨🇦", count: 50)).unicodeScalars.count, 80)
        XCTAssertNil(Limits.cleanDeviceName(String(repeating: "🇨🇦", count: 21)))
        XCTAssertNotNil(Limits.cleanDeviceName(String(repeating: "🇨🇦", count: 20)))
        XCTAssertEqual(Limits.cleanName("\u{00A0}Milk\u{3000}"), "Milk")
        for invisible in ["\u{200B}", "\u{200D}\u{200D}", "\u{FE0F}", "\u{3164}", "\u{2800}", "\u{034F}", "\u{E0101}"] {
            XCTAssertNil(Limits.cleanName(invisible), invisible.debugDescription)
            XCTAssertNil(Limits.cleanDeviceName(invisible), invisible.debugDescription)
        }
        XCTAssertEqual(Limits.cleanName("👩‍👧"), "👩‍👧")
        XCTAssertEqual(Limits.cleanName("نام\u{200C}ها"), "نام\u{200C}ها")
        XCTAssertNil(Limits.cleanName("Mi\u{0007}lk"))
        XCTAssertNil(Limits.cleanName("\u{202E}Milk"))
        XCTAssertEqual(Limits.cleanCalendarName(" Family "), "Family")
        XCTAssertNotNil(Limits.cleanCalendarName(String(repeating: "n", count: 60)))
        XCTAssertNil(Limits.cleanCalendarName(String(repeating: "n", count: 61)))
        XCTAssertNotNil(Limits.cleanCalendarName(String(repeating: "📅", count: 30)))
        XCTAssertNil(Limits.cleanCalendarName(String(repeating: "📅", count: 31)))
        XCTAssertEqual(Limits.emojiLength, 16)
        XCTAssertEqual(Limits.cleanEmoji("ab🛏️"), "🛏️")
        XCTAssertEqual(Limits.cleanEmoji("👨‍👩‍👧‍👦"), "👨‍👩‍👧‍👦")
        XCTAssertEqual(Limits.cleanEmoji(""), "")
        XCTAssertEqual(Limits.cleanEmoji("e" + String(repeating: "\u{0301}", count: 16)), "")
        XCTAssertTrue(Limits.isHexColor("#00a36C"))
        XCTAssertFalse(Limits.isHexColor("00A36C"))
        XCTAssertFalse(Limits.isHexColor("#00A36"))
        XCTAssertFalse(Limits.isHexColor("#00A36CFF"))
    }
}
