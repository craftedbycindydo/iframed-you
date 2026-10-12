import XCTest
@testable import SkylitCore

@MainActor
final class TccClimateStoreTests: XCTestCase {
    private var server: FakeTccServer!
    private var clock: TccClock!
    private var saved: InMemoryTccCredentialStore!

    override func setUp() async throws {
        server = FakeTccServer.sample()
        clock = TccClock()
        saved = InMemoryTccCredentialStore(FakeTccServer.demoCredentials)
    }

    private func makeStore() -> ClimateStore {
        let clock = clock!
        let client = TccClient(transport: server, defaults: tccDefaults(), now: { clock.now })
        return ClimateStore(client: client, credentials: saved, debounce: .milliseconds(60), now: { clock.now })
    }

    private func loaded() async -> ClimateStore {
        let store = makeStore()
        await store.start()
        await store.refresh()
        return store
    }

    private func settle(_ milliseconds: Int = 400) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    func testSignInFlowFromSignedOutToReady() async {
        saved.clear()
        let store = makeStore()
        await store.start()
        XCTAssertEqual(store.phase, .signedOut)
        await store.refresh()
        XCTAssertTrue(server.calls.isEmpty)
        await store.signIn(username: "  home@example.com ", password: "nope")
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertEqual(store.signInError, "Honeywell didn't accept that email and password.")
        XCTAssertNil(saved.load())
        await store.signIn(username: "", password: "x")
        await store.signIn(username: "home@example.com", password: "")
        XCTAssertEqual(server.loginCount, 1)
        await store.signIn(username: "home@example.com ", password: "demo-password")
        XCTAssertEqual(store.phase, .ready)
        XCTAssertNil(store.signInError)
        XCTAssertEqual(saved.load(), FakeTccServer.demoCredentials)
        XCTAssertEqual(store.thermostats.map(\.name), ["Level-0", "level-1"])
        XCTAssertEqual(store.lastUpdated, clock.now)
        XCTAssertTrue(store.canControl)
    }

    func testSavedCredentialsLoadWithoutAsking() async {
        let store = makeStore()
        XCTAssertEqual(store.phase, .loading)
        await store.start()
        await store.refresh()
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.thermostats.count, 2)
        XCTAssertEqual(server.loginCount, 1)
        await store.refresh()
        XCTAssertEqual(server.loginCount, 1)
        XCTAssertEqual(server.calls.filter { $0.path.contains("GetLocationListData") }.count, 2)
    }

    func testFiveTapsSendOneDebouncedRequestAndReconcile() async throws {
        let store = await loaded()
        let readsBefore = server.reads.count
        for _ in 1...5 { store.adjust(1001, by: 1) }
        XCTAssertEqual(store.thermostats[0].heatSetpoint, 75)
        XCTAssertTrue(server.writes.isEmpty)
        await settle()
        XCTAssertEqual(server.writes.count, 1)
        let body = try XCTUnwrap(server.writes.first?.json)
        XCTAssertEqual(body["HeatSetpoint"] as? Double, 75)
        XCTAssertEqual(body["DeviceID"] as? Int, 1001)
        XCTAssertEqual(store.thermostats[0].heatSetpoint, 75)
        XCTAssertEqual(server.reads.count, readsBefore + 2)
        XCTAssertNil(store.notice)

        server.updateUI(1001, ["HeatSetpoint": 71])
        await store.refresh()
        XCTAssertEqual(store.thermostats[0].heatSetpoint, 71)
    }

    func testTapsSpreadAcrossTheDebounceWindowStillCollapse() async {
        let store = await loaded()
        store.adjust(1002, by: -1)
        try? await Task.sleep(for: .milliseconds(25))
        store.adjust(1002, by: -1)
        try? await Task.sleep(for: .milliseconds(25))
        store.adjust(1002, by: -1)
        XCTAssertEqual(store.thermostats[1].coolSetpoint, 73)
        await settle()
        XCTAssertEqual(server.writes.count, 1)
        XCTAssertEqual(server.writes.first?.json?["CoolSetpoint"] as? Double, 73)
        XCTAssertEqual(server.writes.first?.json?["HeatSetpoint"] as? Double, 62)
    }

    func testStepperStopsAtTheDeviceLimitsAndUsesTheHoldKind() async throws {
        server.updateUI(1001, ["HeatSetpoint": 89, "StatusHeat": 0, "StatusCool": 0])
        let store = await loaded()
        store.holdKind = .permanent
        for _ in 1...6 { store.adjust(1001, by: 1) }
        XCTAssertEqual(store.thermostats[0].heatSetpoint, 90)
        await settle()
        XCTAssertEqual(server.writes.count, 1)
        let body = try XCTUnwrap(server.writes.first?.json)
        XCTAssertEqual(body["HeatSetpoint"] as? Double, 90)
        XCTAssertEqual(body["StatusHeat"] as? Int, 2)
        store.adjust(1001, by: 1)
        await settle(200)
        XCTAssertEqual(server.writes.count, 1)
    }

    func testModeAndResumeAreSentAndReflected() async throws {
        let store = await loaded()
        await store.setMode(1001, to: .cool)
        XCTAssertEqual(server.writes.last?.json?["SystemSwitch"] as? Int, 3)
        XCTAssertEqual(store.thermostats[0].mode, .cool)
        await store.setMode(1001, to: .off)
        XCTAssertEqual(server.writes.count, 1)
        XCTAssertEqual(store.notice, "This thermostat doesn't allow that.")
        await store.resumeSchedule(1001)
        XCTAssertEqual(server.writes.last?.json?["StatusHeat"] as? Int, 0)
        XCTAssertEqual(store.thermostats[0].hold, .schedule)
    }

    func testRejectedChangeRevertsAndExplains() async {
        let store = await loaded()
        server.setRejectsWrites(true)
        store.adjust(1001, by: 2)
        XCTAssertEqual(store.thermostats[0].heatSetpoint, 72)
        await settle()
        XCTAssertEqual(store.thermostats[0].heatSetpoint, 70)
        XCTAssertEqual(store.notice, "The thermostat didn't accept that change.")
    }

    func testOfflineKeepsLastReadingsAndBlocksControlUntilRecovery() async {
        let store = await loaded()
        server.setUnreachable(true)
        await store.refresh()
        XCTAssertEqual(store.trouble, .offline)
        XCTAssertEqual(store.failures, 1)
        XCTAssertEqual(store.thermostats.count, 2)
        XCTAssertFalse(store.canControl)
        store.adjust(1001, by: 1)
        XCTAssertEqual(store.thermostats[0].heatSetpoint, 70)
        await store.refresh()
        XCTAssertEqual(store.failures, 2)
        server.setUnreachable(false)
        server.queue(.status(503))
        await store.refresh()
        XCTAssertEqual(store.trouble, .unavailable)
        XCTAssertEqual(store.failures, 3)
        await store.refresh()
        XCTAssertNil(store.trouble)
        XCTAssertEqual(store.failures, 0)
        XCTAssertTrue(store.canControl)
    }

    func testOldReadingsAreStale() async {
        let store = await loaded()
        XCTAssertFalse(store.isStale)
        clock.advance(181)
        XCTAssertTrue(store.isStale)
        XCTAssertFalse(store.canControl)
        await store.refresh()
        XCTAssertFalse(store.isStale)
    }

    func testThrottledSignInShowsLockedWithoutHammering() async {
        server.setLogin(.tooManyAttempts)
        let store = await loaded()
        XCTAssertEqual(store.phase, .locked(until: clock.now.addingTimeInterval(600)))
        let calls = server.calls.count
        await store.refresh()
        await store.refresh()
        XCTAssertEqual(server.calls.count, calls)
        XCTAssertNotNil(saved.load())
        server.setLogin(.normal)
        clock.advance(601)
        await store.refresh()
        XCTAssertEqual(store.phase, .ready)
    }

    func testRejectedSavedPasswordAsksForSignInAgain() async {
        server.setPassword("changed-elsewhere")
        let store = await loaded()
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(saved.load())
        XCTAssertNotNil(store.signInError)
        let calls = server.calls.count
        await store.refresh()
        XCTAssertEqual(server.calls.count, calls)
    }

    func testLockedSignInAttemptExplainsTheWait() async {
        saved.clear()
        server.setLogin(.tooManyAttempts)
        let store = makeStore()
        await store.start()
        await store.signIn(username: "home@example.com", password: "demo-password")
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertTrue(store.signInError?.contains("paused sign-in") == true)
        XCTAssertNil(saved.load())
    }

    func testConcurrentRefreshesAreSingleFlight() async {
        let store = await loaded()
        let before = server.reads.count
        async let first: Void = store.refresh()
        async let second: Void = store.refresh()
        async let third: Void = store.refresh()
        async let fourth: Void = store.refresh()
        _ = await (first, second, third, fourth)
        let passes = (server.reads.count - before) / 2
        XCTAssertTrue((1...3).contains(passes), "\(passes) passes for four overlapping requests")
    }

    func testPollingRunsUntilCancelled() async {
        let store = makeStore()
        let polling = Task { await store.runPolling(every: .milliseconds(40)) }
        await settle(300)
        polling.cancel()
        await polling.value
        let reads = server.reads.count
        XCTAssertGreaterThanOrEqual(reads, 6)
        XCTAssertEqual(store.phase, .ready)
        await settle(150)
        XCTAssertEqual(server.reads.count, reads)
        XCTAssertEqual(server.loginCount, 1)
    }

    func testRelaunchReusesTheSavedSessionInsteadOfSigningInAgain() async {
        let first = await loaded()
        XCTAssertEqual(first.phase, .ready)
        XCTAssertEqual(server.loginCount, 1)
        XCTAssertNotNil(saved.loadSession())
        for _ in 0..<3 {
            let again = await loaded()
            XCTAssertEqual(again.phase, .ready)
        }
        XCTAssertEqual(server.loginCount, 1)
    }

    func testRelaunchWithADeadSessionSignsInOnceAfterTheThrottleWindow() async {
        _ = await loaded()
        server.expireSessions()
        clock.advance(TccClient.reloginInterval + 1)
        let again = await loaded()
        XCTAssertEqual(again.phase, .ready)
        XCTAssertEqual(server.loginCount, 2)
    }

    func testSignOutAndRejectedPasswordForgetTheSavedSession() async {
        let store = await loaded()
        await store.signOut()
        XCTAssertNil(saved.loadSession())
        saved.save(FakeTccServer.demoCredentials)
        let again = await loaded()
        XCTAssertEqual(server.loginCount, 2)
        server.setPassword("changed")
        server.expireSessions()
        clock.advance(TccClient.reloginInterval + 1)
        await again.refresh()
        XCTAssertEqual(again.phase, .signedOut)
        XCTAssertNil(saved.loadSession())
    }

    func testSignOutClearsEverything() async {
        let store = await loaded()
        store.adjust(1001, by: 1)
        await store.signOut()
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertTrue(store.thermostats.isEmpty)
        XCTAssertNil(saved.load())
        XCTAssertEqual(server.calls.last?.path, "/portal/Account/LogOff")
        await settle(200)
        XCTAssertTrue(server.writes.isEmpty)
    }

    func testOfflineThermostatCannotBeAdjusted() async {
        server.update(1002) { $0["communicationLost"] = true }
        let store = await loaded()
        XCTAssertFalse(store.thermostats[1].isOnline)
        store.adjust(1002, by: 1)
        XCTAssertEqual(store.thermostats[1].coolSetpoint, 76)
        await settle(200)
        XCTAssertTrue(server.writes.isEmpty)
    }
}
