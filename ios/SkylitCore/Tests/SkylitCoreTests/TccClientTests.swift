import XCTest
@testable import SkylitCore

final class TccClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_791_741_600)

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

func tccDefaults() -> UserDefaults {
    let suite = "skylit-tcc-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

func tccFailure(_ work: () async throws -> Void) async -> TccError? {
    do {
        try await work()
        return nil
    } catch {
        return error as? TccError ?? .unexpectedResponse
    }
}

final class TccClientTests: XCTestCase {
    private let good = FakeTccServer.demoCredentials
    private let wrong = TccCredentials(username: "home@example.com", password: "nope")
    private var server: FakeTccServer!
    private var clock: TccClock!
    private var defaults: UserDefaults!
    private var client: TccClient!

    override func setUp() {
        server = FakeTccServer.sample()
        clock = TccClock()
        defaults = tccDefaults()
        client = makeClient()
    }

    private func makeClient() -> TccClient {
        let clock = clock!
        return TccClient(transport: server, defaults: defaults, now: { clock.now })
    }

    private func device(_ id: Int = 1001) -> TccDevice {
        TccDevice(id: id, name: id == 1001 ? "Level-0" : "level-1")
    }

    func testLoginSendsFormOnceAndCarriesCookiesAfterwards() async throws {
        try await client.signIn(good)
        let calls = server.calls
        XCTAssertEqual(calls[0].method, "POST")
        XCTAssertEqual(calls[0].url.absoluteString, "https://mytotalconnectcomfort.com/portal")
        XCTAssertEqual(calls[0].headers["Content-Type"], "application/x-www-form-urlencoded")
        XCTAssertEqual(calls[0].headers["X-Requested-With"], "XMLHttpRequest")
        XCTAssertNil(calls[0].headers["Cookie"])
        XCTAssertTrue(calls[0].text.contains("UserName=home%40example.com"))
        XCTAssertTrue(calls[0].text.contains("Password=demo-password"))
        XCTAssertTrue(calls[0].text.contains("RememberMe=false"))
        XCTAssertTrue(calls[0].text.hasPrefix("timeOffset="))
        XCTAssertNil(calls[0].url.query)
        XCTAssertEqual(calls.map(\.method), ["POST", "GET", "GET", "GET", "GET"])
        XCTAssertEqual(calls.map(\.path), ["/portal", "/portal", "/portal/4242/Zones", "/portal", "/portal/4242/Zones"])
        XCTAssertEqual(calls[1].headers["Cookie"], ".ASPXAUTH_TRUEHOME=SESSION1; ASP.NET_SessionId=abc1; thlang=en-US")
        let hasSession = await client.hasSession
        XCTAssertTrue(hasSession)
        _ = try await client.thermostat(device())
        XCTAssertEqual(server.loginCount, 1)
        XCTAssertEqual(server.calls.last?.headers["Cookie"], ".ASPXAUTH_TRUEHOME=SESSION1; ASP.NET_SessionId=abc1; thlang=en-US")
        XCTAssertTrue(server.calls.allSatisfy { $0.url.scheme == "https" && $0.url.host == "mytotalconnectcomfort.com" })
    }

    func testCookieParsingSurvivesMalformedExpiryAndMergedHeaders() {
        let merged = ".ASPXAUTH_TRUEHOME=ABC123; expires=Sun, 11-Oct-2026 25:61:00 GMT; path=/; secure; HttpOnly, "
            + "ASP.NET_SessionId=xyz; path=/, gone=; expires=Thu, 01-Jan-1970 00:00:00 GMT, odd=a=b"
        let pairs = TccClient.cookiePairs(merged)
        XCTAssertEqual(pairs.map(\.0), [".ASPXAUTH_TRUEHOME", "ASP.NET_SessionId", "gone", "odd"])
        XCTAssertEqual(pairs.map(\.1), ["ABC123", "xyz", "", "a=b"])
        XCTAssertTrue(TccClient.cookiePairs("").isEmpty)
        XCTAssertTrue(TccClient.cookiePairs("garbage without equals").isEmpty)
    }

    func testFormEncodingEscapesReservedCharacters() {
        XCTAssertEqual(TccClient.formEncoded("a@b.co"), "a%40b.co")
        XCTAssertEqual(TccClient.formEncoded("p&w=1 +%"), "p%26w%3D1%20%2B%25")
    }

    func testWrongPasswordIsReportedAndThirdFailureLocks() async {
        for attempt in 1...3 {
            let failure = await tccFailure { try await self.client.signIn(self.wrong) }
            XCTAssertEqual(failure, .badCredentials, "attempt \(attempt)")
        }
        let state = await client.loginGuard
        XCTAssertEqual(state.failures, 3)
        XCTAssertEqual(state.lockedUntil, clock.now.addingTimeInterval(600))
        let before = server.calls.count
        let refused = await tccFailure { try await self.client.signIn(self.good) }
        XCTAssertEqual(refused, .locked(until: clock.now.addingTimeInterval(600)))
        XCTAssertEqual(server.calls.count, before)
        let hasSession = await client.hasSession
        XCTAssertFalse(hasSession)
    }

    func testLockSurvivesRelaunchThenDoublesAndClearsOnSuccess() async throws {
        for _ in 1...3 { _ = await tccFailure { try await self.client.signIn(self.wrong) } }
        let relaunched = makeClient()
        let before = server.calls.count
        let refused = await tccFailure { try await relaunched.signIn(self.good) }
        XCTAssertEqual(refused, .locked(until: clock.now.addingTimeInterval(600)))
        XCTAssertEqual(server.calls.count, before)
        clock.advance(601)
        let again = await tccFailure { try await relaunched.signIn(self.wrong) }
        XCTAssertEqual(again, .badCredentials)
        let doubled = await relaunched.loginGuard
        XCTAssertEqual(doubled.lockedUntil, clock.now.addingTimeInterval(1200))
        clock.advance(1201)
        try await relaunched.signIn(good)
        let cleared = await relaunched.loginGuard
        XCTAssertEqual(cleared, TccLoginGuard())
        let fresh = makeClient()
        let persisted = await fresh.loginGuard
        XCTAssertEqual(persisted, TccLoginGuard())
    }

    func testTooManyAttemptsRedirectLocksImmediately() async {
        server.setLogin(.tooManyAttempts)
        let failure = await tccFailure { try await self.client.signIn(self.good) }
        XCTAssertEqual(failure, .locked(until: clock.now.addingTimeInterval(600)))
        XCTAssertEqual(server.calls.count, 1)
        server.setLogin(.normal)
        let refused = await tccFailure { try await self.client.signIn(self.good) }
        XCTAssertEqual(refused, .locked(until: clock.now.addingTimeInterval(600)))
        XCTAssertEqual(server.calls.count, 1)
    }

    func testEmptyAuthCookieAndUnauthorizedCountAsLoginFailures() async {
        server.setLogin(.emptyCookie)
        let empty = await tccFailure { try await self.client.signIn(self.good) }
        XCTAssertEqual(empty, .loginFailed)
        server.setLogin(.unauthorized)
        let refused = await tccFailure { try await self.client.signIn(self.good) }
        XCTAssertEqual(refused, .badCredentials)
        let state = await client.loginGuard
        XCTAssertEqual(state.failures, 2)
        XCTAssertNil(state.lockedUntil)
    }

    func testSuccessfulReadClearsEarlierFailures() async throws {
        _ = await tccFailure { try await self.client.signIn(self.wrong) }
        _ = await tccFailure { try await self.client.signIn(self.wrong) }
        try await client.signIn(good)
        _ = try await client.thermostat(device())
        let state = await client.loginGuard
        XCTAssertEqual(state.failures, 0)
    }

    func testRedirectsToAnotherHostOrSchemeAreRefusedWithoutBeingFollowed() async {
        for target in ["https://evil.example/portal", "http://mytotalconnectcomfort.com/portal", "https://mytotalconnectcomfort.com.evil.example/",
                       "https://user@mytotalconnectcomfort.com/portal", "https://mytotalconnectcomfort.com:8443/portal", "//evil.example/x"] {
            server.setLogin(.redirect(target))
            let failure = await tccFailure { try await self.client.signIn(self.good) }
            XCTAssertEqual(failure, .foreignHost, target)
        }
        XCTAssertEqual(server.calls.count, 6)
        XCTAssertTrue(server.calls.allSatisfy { $0.url.host == "mytotalconnectcomfort.com" && $0.url.scheme == "https" })
        let state = await client.loginGuard
        XCTAssertEqual(state.failures, 0)
    }

    func testRedirectLoopsEndAsUnavailable() async {
        server.setLogin(.redirect("/portal/Loop"))
        let failure = await tccFailure { try await self.client.signIn(self.good) }
        XCTAssertEqual(failure, .unavailable(status: 310))
        XCTAssertEqual(server.calls.count, 6)
        server.setLogin(.redirect("/portal/Error?aspxerrorpath=/portal"))
        let errorPage = await tccFailure { try await self.client.signIn(self.good) }
        XCTAssertEqual(errorPage, .unavailable(status: 302))
    }

    func testTransportRefusesForeignHostsBeforeAnyNetworkUse() async {
        let transport = TccURLSessionTransport()
        for address in ["https://example.com/portal", "http://mytotalconnectcomfort.com/portal", "https://mytotalconnectcomfort.com:444/"] {
            let failure = await tccFailure { _ = try await transport.send(URLRequest(url: URL(string: address)!), body: nil) }
            XCTAssertEqual(failure, .foreignHost, address)
        }
    }

    func testExpiredSessionLogsInAgainOnceAfterTenMinutes() async throws {
        try await client.signIn(good)
        clock.advance(601)
        server.expireSessions()
        let reading = try await client.thermostat(device())
        XCTAssertEqual(reading.name, "Level-0")
        XCTAssertEqual(server.loginCount, 2)
        XCTAssertEqual(server.calls.last?.headers["Cookie"], ".ASPXAUTH_TRUEHOME=SESSION2; ASP.NET_SessionId=abc2; thlang=en-US")
    }

    func testReloginIsThrottledToOncePerTenMinutes() async throws {
        try await client.signIn(good)
        clock.advance(120)
        server.expireSessions()
        for _ in 1...4 {
            let failure = await tccFailure { _ = try await self.client.thermostat(self.device()) }
            XCTAssertEqual(failure, .sessionExpired)
            clock.advance(60)
        }
        XCTAssertEqual(server.loginCount, 1)
        clock.advance(300)
        _ = try await client.thermostat(device())
        XCTAssertEqual(server.loginCount, 2)
        server.expireSessions()
        let again = await tccFailure { _ = try await self.client.thermostat(self.device()) }
        XCTAssertEqual(again, .sessionExpired)
        XCTAssertEqual(server.loginCount, 2)
    }

    func testFirstUseLogsInWithSavedCredentialsAndConcurrentCallsShareOneLogin() async throws {
        await client.setCredentials(good)
        async let first = client.thermostat(device(1001))
        async let second = client.thermostat(device(1002))
        async let third = client.locations()
        let results = try await (first, second, third)
        XCTAssertEqual(results.0.name, "Level-0")
        XCTAssertEqual(results.1.name, "level-1")
        XCTAssertEqual(results.2.count, 1)
        XCTAssertEqual(server.loginCount, 1)
    }

    func testCallsWithoutCredentialsNeedSignIn() async {
        let failure = await tccFailure { _ = try await self.client.locations() }
        XCTAssertEqual(failure, .needsSignIn)
        XCTAssertTrue(server.calls.isEmpty)
    }

    func testLocationsAndDevicesAreListedAndPagingStopsAtTheFirstEmptyPage() async throws {
        try await client.signIn(good)
        let locations = try await client.locations()
        XCTAssertEqual(locations.map(\.id), [4242])
        XCTAssertEqual(locations[0].devices, [TccDevice(id: 1001, name: "Level-0", macId: "00D02D0003E9"), TccDevice(id: 1002, name: "level-1", macId: "00D02D0003EA")])
        let listing = server.calls.filter { $0.path.contains("GetLocationListData") }
        XCTAssertEqual(listing.map(\.url.absoluteString), ["https://mytotalconnectcomfort.com/portal/Location/GetLocationListData/?page=1&filter=",
                                                          "https://mytotalconnectcomfort.com/portal/Location/GetLocationListData/?page=2&filter="])
        XCTAssertTrue(listing.allSatisfy { $0.method == "POST" && $0.body == nil })
    }

    func testEveryReadFieldIsParsed() async throws {
        try await client.signIn(good)
        let heat = try await client.thermostat(device(1001))
        XCTAssertEqual(heat.id, 1001)
        XCTAssertEqual(heat.name, "Level-0")
        XCTAssertTrue(heat.isOnline)
        XCTAssertEqual(heat.units, .fahrenheit)
        XCTAssertEqual(heat.indoorTemperature, 69)
        XCTAssertEqual(heat.indoorHumidity, 41)
        XCTAssertEqual(heat.outdoorTemperature, 58)
        XCTAssertEqual(heat.outdoorHumidity, 62)
        XCTAssertEqual(heat.heatSetpoint, 70)
        XCTAssertEqual(heat.coolSetpoint, 78)
        XCTAssertEqual(heat.heatRange, 40...90)
        XCTAssertEqual(heat.coolRange, 50...99)
        XCTAssertEqual(heat.deadband, 0)
        XCTAssertEqual(heat.mode, .heat)
        XCTAssertEqual(heat.allowedModes, [.heat, .cool, .off])
        XCTAssertTrue(heat.canSwitchHeatCool)
        XCTAssertEqual(heat.heatHold, .permanent)
        XCTAssertEqual(heat.hold, .permanent)
        XCTAssertEqual(heat.fanMode, .auto)
        XCTAssertTrue(heat.isFanRunning)
        XCTAssertEqual(heat.running, .heating)
        XCTAssertEqual(heat.activeSetpoint, .heat)
        let cool = try await client.thermostat(device(1002))
        XCTAssertEqual(cool.mode, .cool)
        XCTAssertEqual(cool.activeSetpoint, .cool)
        XCTAssertEqual(cool.hold, .temporary(untilMinutes: 18 * 60))
        XCTAssertEqual(cool.running, .idle)
        XCTAssertFalse(cool.isFanRunning)
        let reads = server.reads
        XCTAssertEqual(reads.map(\.method), ["GET", "GET"])
        XCTAssertEqual(reads[0].path, "/portal/Device/CheckDataSession/1001")
        let first = Int(reads[0].url.query!.dropFirst(2))!
        let second = Int(reads[1].url.query!.dropFirst(2))!
        XCTAssertEqual(second, first + 1)
    }

    func testMissingNullAndUnknownFieldsDoNotBreakParsing() {
        let bare = TccThermostat(device: device(), payload: [:])
        XCTAssertFalse(bare.isOnline)
        XCTAssertNil(bare.indoorTemperature)
        XCTAssertNil(bare.mode)
        XCTAssertNil(bare.hold)
        XCTAssertNil(bare.heatRange)
        XCTAssertNil(bare.fanMode)
        XCTAssertNil(bare.running)
        XCTAssertNil(bare.activeSetpoint)
        XCTAssertTrue(bare.allowedModes.isEmpty)
        XCTAssertEqual(bare.units, .fahrenheit)

        var ui = FakeTccServer.ui(mode: 9, indoor: 70, heat: 68, cool: 75, status: 7)
        ui["EquipmentOutputStatus"] = NSNull()
        ui["DispTemperature"] = NSNull()
        ui["OutdoorTemperatureAvailable"] = false
        ui["OutdoorHumidityAvailable"] = NSNull()
        ui["IndoorHumiditySensorNotFault"] = false
        ui["HeatLowerSetptLimit"] = 95
        ui["CoolUpperSetptLimit"] = "99"
        ui["HeatNextPeriod"] = 200
        let odd = TccThermostat(device: device(), payload: ["deviceLive": true, "communicationLost": true,
                                                            "latestData": ["uiData": ui, "hasFan": false, "fanData": ["fanMode": 1, "fanIsRunning": true]]])
        XCTAssertFalse(odd.isOnline)
        XCTAssertNil(odd.indoorTemperature)
        XCTAssertNil(odd.running)
        XCTAssertNil(odd.outdoorTemperature)
        XCTAssertNil(odd.outdoorHumidity)
        XCTAssertNil(odd.indoorHumidity)
        XCTAssertNil(odd.mode)
        XCTAssertNil(odd.heatHold)
        XCTAssertNil(odd.heatRange)
        XCTAssertNil(odd.coolRange)
        XCTAssertNil(odd.fanMode)
        XCTAssertFalse(odd.isFanRunning)

        for (position, mode) in [(0, TccMode.emergencyHeat), (1, .heat), (2, .off), (3, .cool), (4, .auto), (5, .auto)] {
            let reading = TccThermostat(device: device(), payload: ["latestData": ["uiData": ["SystemSwitchPosition": position]]])
            XCTAssertEqual(reading.mode, mode)
        }
        let temporary = TccThermostat(device: device(), payload: ["latestData": ["uiData": ["SystemSwitchPosition": 1, "StatusHeat": 1, "HeatNextPeriod": 200]]])
        XCTAssertEqual(temporary.hold, .temporary(untilMinutes: nil))
        let scheduled = TccThermostat(device: device(), payload: ["latestData": ["uiData": ["SystemSwitchPosition": 2, "StatusHeat": 0]]])
        XCTAssertEqual(scheduled.hold, .schedule)
    }

    func testCelsiusAccountsKeepHalfDegreesAndTheirOwnLimits() async throws {
        server.addThermostat(id: 1003, name: "Loft", ui: FakeTccServer.ui(mode: 1, indoor: 20.5, heat: 21.5, cool: 25, status: 0, units: "C"))
        try await client.signIn(good)
        let loft = try await client.thermostat(TccDevice(id: 1003, name: "Loft"))
        XCTAssertEqual(loft.units, .celsius)
        XCTAssertEqual(loft.units.step, 0.5)
        XCTAssertEqual(loft.indoorTemperature, 20.5)
        XCTAssertEqual(loft.heatSetpoint, 21.5)
        XCTAssertEqual(loft.heatRange, 4.5...32)
        try await client.setSetpoint(.heat, to: 22.5, on: loft)
        XCTAssertEqual(server.writes.last?.json?["HeatSetpoint"] as? Double, 22.5)
        XCTAssertEqual(server.ui(1003)["HeatSetpoint"] as? Double, 22.5)
    }

    func testSetpointOnScheduleCreatesTemporaryHoldUntilNextPeriod() async throws {
        server.updateUI(1001, ["StatusHeat": 0, "StatusCool": 0, "HeatNextPeriod": 88, "CoolNextPeriod": 90])
        try await client.signIn(good)
        let reading = try await client.thermostat(device())
        try await client.setSetpoint(.heat, to: 72, on: reading)
        let call = try XCTUnwrap(server.writes.last)
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.path, "/portal/Device/SubmitControlScreenChanges")
        XCTAssertEqual(call.headers["Content-Type"], "application/json")
        let body = try XCTUnwrap(call.json)
        XCTAssertEqual(Set(body.keys), ["DeviceID", "SystemSwitch", "HeatSetpoint", "CoolSetpoint", "HeatNextPeriod", "CoolNextPeriod", "StatusHeat", "StatusCool", "FanMode"])
        XCTAssertEqual(body["DeviceID"] as? Int, 1001)
        XCTAssertEqual(body["HeatSetpoint"] as? Double, 72)
        XCTAssertEqual(body["CoolSetpoint"] as? Double, 78)
        XCTAssertEqual(body["StatusHeat"] as? Int, 1)
        XCTAssertEqual(body["StatusCool"] as? Int, 1)
        XCTAssertEqual(body["HeatNextPeriod"] as? Int, 88)
        XCTAssertEqual(body["CoolNextPeriod"] as? Int, 88)
        XCTAssertTrue(body["SystemSwitch"] is NSNull)
        XCTAssertTrue(body["FanMode"] is NSNull)
        XCTAssertTrue(call.text.contains("\"HeatSetpoint\":72,") || call.text.contains("\"HeatSetpoint\":72}"))
    }

    func testSetpointWhileHoldingKeepsTheExistingHoldAndPermanentIsExplicit() throws {
        var reading = TccThermostat(device: device(), payload: ["latestData": ["uiData": FakeTccServer.ui(mode: 3, indoor: 75, heat: 62, cool: 76, status: 2)]])
        let kept = try reading.setpointChange(.cool, to: 74)
        XCTAssertEqual(kept.coolSetpoint, 74)
        XCTAssertEqual(kept.heatSetpoint, 62)
        XCTAssertNil(kept.statusHeat)
        XCTAssertNil(kept.statusCool)
        XCTAssertNil(kept.coolNextPeriod)
        reading.heatHold = .temporary
        reading.coolHold = .temporary
        XCTAssertNil(try reading.setpointChange(.cool, to: 74).statusCool)
        reading.heatHold = .permanent
        reading.coolHold = .schedule
        XCTAssertEqual(try reading.setpointChange(.cool, to: 74).statusCool, 1)
        reading.coolHold = nil
        XCTAssertEqual(try reading.setpointChange(.cool, to: 74).statusCool, 1)
        reading.heatHold = .schedule
        reading.coolHold = .schedule
        let permanent = try reading.setpointChange(.cool, to: 74, hold: .permanent)
        XCTAssertEqual(permanent.statusHeat, 2)
        XCTAssertEqual(permanent.statusCool, 2)
        XCTAssertNil(permanent.heatNextPeriod)
        reading.coolNextPeriod = nil
        let open = try reading.setpointChange(.cool, to: 74)
        XCTAssertEqual(open.statusCool, 1)
        XCTAssertNil(open.coolNextPeriod)
        XCTAssertNil(open.heatNextPeriod)
    }

    func testLimitsAndDeadbandAreEnforcedBeforeAnythingIsSent() async throws {
        try await client.signIn(good)
        var reading = try await client.thermostat(device())
        let before = server.calls.count
        for value in [39.0, 91, -5, 1000] {
            let failure = await tccFailure { try await self.client.setSetpoint(.heat, to: value, on: reading) }
            XCTAssertEqual(failure, .outOfRange)
        }
        let cool = await tccFailure { try await self.client.setSetpoint(.cool, to: 49, on: reading) }
        XCTAssertEqual(cool, .outOfRange)
        XCTAssertEqual(server.calls.count, before)
        XCTAssertEqual(try reading.setpointChange(.heat, to: 40).heatSetpoint, 40)
        XCTAssertEqual(try reading.setpointChange(.heat, to: 90).heatSetpoint, 90)

        reading.deadband = 3
        let pushedUp = try reading.setpointChange(.heat, to: 76)
        XCTAssertEqual(pushedUp.heatSetpoint, 76)
        XCTAssertEqual(pushedUp.coolSetpoint, 79)
        let pushedDown = try reading.setpointChange(.cool, to: 72)
        XCTAssertEqual(pushedDown.coolSetpoint, 72)
        XCTAssertEqual(pushedDown.heatSetpoint, 69)
        reading.coolRange = 50...80
        reading.coolSetpoint = 80
        XCTAssertThrowsError(try reading.setpointChange(.heat, to: 78)) { XCTAssertEqual($0 as? TccError, .outOfRange) }
        reading.heatRange = nil
        XCTAssertThrowsError(try reading.setpointChange(.heat, to: 70)) { XCTAssertEqual($0 as? TccError, .notAllowed) }
    }

    func testModeSwitchIsHeatOrCoolOnlyAndRespectsTheDevice() async throws {
        try await client.signIn(good)
        var reading = try await client.thermostat(device())
        try await client.setMode(.cool, on: reading)
        let body = try XCTUnwrap(server.writes.last?.json)
        XCTAssertEqual(body["SystemSwitch"] as? Int, 3)
        XCTAssertTrue(body["HeatSetpoint"] is NSNull)
        XCTAssertTrue(body["StatusHeat"] is NSNull)
        XCTAssertEqual(server.ui(1001)["SystemSwitchPosition"] as? Int, 3)
        XCTAssertEqual(try reading.modeChange(.heat).systemSwitch, 1)
        let sent = server.writes.count
        for mode in [TccMode.off, .auto, .emergencyHeat] {
            let failure = await tccFailure { try await self.client.setMode(mode, on: reading) }
            XCTAssertEqual(failure, .notAllowed)
        }
        reading.allowedModes = [.heat, .off, .auto, .emergencyHeat]
        XCTAssertFalse(reading.canSwitchHeatCool)
        let failure = await tccFailure { try await self.client.setMode(.cool, on: reading) }
        XCTAssertEqual(failure, .notAllowed)
        XCTAssertEqual(server.writes.count, sent)
    }

    func testResumeScheduleClearsBothHolds() async throws {
        try await client.signIn(good)
        let reading = try await client.thermostat(device())
        try await client.resumeSchedule(on: reading)
        let body = try XCTUnwrap(server.writes.last?.json)
        XCTAssertEqual(body["StatusHeat"] as? Int, 0)
        XCTAssertEqual(body["StatusCool"] as? Int, 0)
        XCTAssertTrue(body["HeatSetpoint"] is NSNull)
        XCTAssertTrue(body["HeatNextPeriod"] is NSNull)
        let after = try await client.thermostat(device())
        XCTAssertEqual(after.hold, .schedule)
    }

    func testRejectedWriteIsAnError() async throws {
        try await client.signIn(good)
        let reading = try await client.thermostat(device())
        server.setRejectsWrites(true)
        let failure = await tccFailure { try await self.client.resumeSchedule(on: reading) }
        XCTAssertEqual(failure, .rejected)
    }

    func testServiceFailuresAreClassified() async throws {
        try await client.signIn(good)
        let cases: [(FakeTccServer.Glitch, TccError)] = [(.status(500), .unavailable(status: 500)), (.status(502), .unavailable(status: 502)),
                                                         (.status(503), .unavailable(status: 503)), (.status(429), .unavailable(status: 429)),
                                                         (.redirect("/portal/Error?aspxerrorpath=/portal/Device/CheckDataSession/1001"), .unavailable(status: 302)),
                                                         (.redirect("https://evil.example/"), .unavailable(status: 302)),
                                                         (.html, .unexpectedResponse), (.oversized, .tooLarge)]
        for (glitch, expected) in cases {
            server.queue(glitch)
            let before = server.calls.count
            let failure = await tccFailure { _ = try await self.client.thermostat(self.device()) }
            XCTAssertEqual(failure, expected)
            XCTAssertEqual(server.calls.count, before + 1)
        }
        server.setUnreachable(true)
        let offline = await tccFailure { _ = try await self.client.thermostat(self.device()) }
        XCTAssertEqual(offline, .network)
        server.setUnreachable(false)
        _ = try await client.thermostat(device())
        XCTAssertEqual(server.loginCount, 1)
    }

    func testBackoffAndLockDurations() {
        XCTAssertEqual([0, 1, 2, 3, 4, 9, 400].map { TccBackoff.delay(failures: $0) }, [60, 120, 240, 480, 600, 600, 600])
        XCTAssertEqual(TccBackoff.delay(failures: -3), 60)
        XCTAssertEqual([0, 2, 3, 4, 5, 8, 9, 50].map { TccBackoff.lock(failures: $0) }, [nil, nil, 600, 1200, 2400, 19200, 21600, 21600])
    }

    func testSignOutPostsLogOffAndForgetsTheSession() async throws {
        try await client.signIn(good)
        await client.signOut()
        XCTAssertEqual(server.calls.last?.path, "/portal/Account/LogOff")
        XCTAssertEqual(server.calls.last?.method, "POST")
        let hasSession = await client.hasSession
        XCTAssertFalse(hasSession)
        let failure = await tccFailure { _ = try await self.client.locations() }
        XCTAssertEqual(failure, .needsSignIn)
    }

    func testCredentialsNeverAppearInDescriptionsAndStoresRoundTrip() {
        let secret = TccCredentials(username: "owner@example.com", password: "hunter2-secret")
        var dumped = ""
        dump(secret, to: &dumped)
        for text in ["\(secret)", String(describing: secret), String(reflecting: secret), dumped, "\([secret])", "\(Optional(secret) as Any)"] {
            XCTAssertFalse(text.contains("hunter2"), text)
            XCTAssertFalse(text.contains("owner@"), text)
        }
        let store = InMemoryTccCredentialStore()
        XCTAssertNil(store.load())
        store.save(secret)
        XCTAssertEqual(store.load(), secret)
        store.clear()
        XCTAssertNil(store.load())
    }

    func testKeychainStoreKeepsTheSessionNextToTheCredentialsAndClearsBothTogether() {
        let store = TccCredentialStore(service: "skylit-tests-tcc-\(UUID().uuidString)")
        let secret = TccCredentials(username: "owner@example.com", password: "hunter2-secret")
        let session = TccSession(cookies: [TccClient.authCookie: "abc", "thlang": "en-US"], lastLogin: Date(timeIntervalSince1970: 1_791_741_600))
        XCTAssertNil(store.loadSession())
        store.save(secret)
        store.saveSession(session)
        XCTAssertEqual(store.load(), secret)
        XCTAssertEqual(store.loadSession(), session)
        store.saveSession(nil)
        XCTAssertNil(store.loadSession())
        XCTAssertEqual(store.load(), secret)
        store.saveSession(session)
        store.clear()
        XCTAssertNil(store.load())
        XCTAssertNil(store.loadSession())
    }

    func testErrorsCarryNoSecretsAndHaveMessages() {
        let all: [TccError] = [.needsSignIn, .badCredentials, .loginFailed, .locked(until: Date()), .sessionExpired, .unavailable(status: 503),
                               .unexpectedResponse, .network, .cancelled, .rejected, .outOfRange, .notAllowed, .foreignHost, .tooLarge]
        XCTAssertTrue(all.allSatisfy { !$0.userMessage.isEmpty })
    }
}
