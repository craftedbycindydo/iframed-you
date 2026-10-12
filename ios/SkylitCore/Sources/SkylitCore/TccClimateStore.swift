import Foundation
import Observation

@MainActor
@Observable
public final class ClimateStore {
    public enum Phase: Equatable, Sendable {
        case signedOut
        case loading
        case ready
        case locked(until: Date)
    }

    public enum Trouble: Equatable, Sendable {
        case offline
        case unavailable
    }

    private struct Pending: Equatable {
        let which: TccSetpoint
        let value: Double
    }

    public static let staleAfter: TimeInterval = 180

    public private(set) var phase = Phase.loading
    public private(set) var trouble: Trouble?
    public private(set) var lastUpdated: Date?
    public private(set) var isSigningIn = false
    public private(set) var signInError: String?
    public private(set) var failures = 0
    public var notice: String?
    public var holdKind = TccHoldKind.untilNextPeriod

    private let client: TccClient
    private let credentials: TccCredentialStoring
    private let now: () -> Date
    private let debounce: Duration
    private var started = false
    private var devices: [TccDevice] = []
    private var readings: [TccThermostat] = []
    private var pending: [Int: Pending] = [:]
    private var sends: [Int: Task<Void, Never>] = [:]
    private var refreshing: Task<Void, Never>?
    private var refreshAgain = false

    public init(client: TccClient, credentials: TccCredentialStoring, debounce: Duration = .seconds(1), now: @escaping () -> Date = Date.init) {
        self.client = client
        self.credentials = credentials
        self.debounce = debounce
        self.now = now
    }

    public var thermostats: [TccThermostat] {
        readings.map { reading in
            guard let change = pending[reading.id] else { return reading }
            var shown = reading
            if change.which == .heat { shown.heatSetpoint = change.value } else { shown.coolSetpoint = change.value }
            return shown
        }
    }

    public var isStale: Bool {
        guard let lastUpdated else { return false }
        return now().timeIntervalSince(lastUpdated) > Self.staleAfter
    }

    public var canControl: Bool {
        phase == .ready && trouble == nil && !isStale
    }

    public func start() async {
        guard !started else { return }
        started = true
        if let saved = credentials.load() {
            await client.setCredentials(saved)
            phase = .loading
        } else {
            phase = .signedOut
        }
    }

    public func signIn(username: String, password: String) async {
        let entered = TccCredentials(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        guard !entered.username.isEmpty, !entered.password.isEmpty, !isSigningIn else { return }
        started = true
        isSigningIn = true
        signInError = nil
        defer { isSigningIn = false }
        do {
            try await client.signIn(entered)
            credentials.save(entered)
            devices = []
            phase = .loading
            await refresh()
        } catch {
            signInError = Self.signInMessage(error)
        }
    }

    public func signOut() async {
        sends.values.forEach { $0.cancel() }
        sends = [:]
        pending = [:]
        credentials.clear()
        await client.signOut()
        devices = []
        readings = []
        lastUpdated = nil
        trouble = nil
        failures = 0
        signInError = nil
        phase = .signedOut
    }

    public func runPolling(every interval: Duration = .seconds(60)) async {
        await start()
        while !Task.isCancelled {
            await refresh()
            let seconds = TccBackoff.delay(failures: failures, base: Double(interval.components.seconds) + Double(interval.components.attoseconds) / 1e18)
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
        }
    }

    public func refresh() async {
        if let running = refreshing {
            refreshAgain = true
            await running.value
            return
        }
        let task = Task {
            repeat {
                refreshAgain = false
                await load()
            } while refreshAgain
        }
        refreshing = task
        await task.value
        refreshing = nil
    }

    private func load() async {
        guard phase != .signedOut else { return }
        do {
            if devices.isEmpty { devices = try await client.locations().flatMap(\.devices) }
            var fresh: [TccThermostat] = []
            for device in devices { fresh.append(try await client.thermostat(device)) }
            guard phase != .signedOut else { return }
            readings = fresh
            lastUpdated = now()
            trouble = nil
            failures = 0
            phase = .ready
        } catch {
            handle(error)
        }
    }

    private func handle(_ error: Error) {
        switch error as? TccError ?? .unexpectedResponse {
        case .cancelled:
            break
        case .needsSignIn, .badCredentials:
            credentials.clear()
            readings = []
            devices = []
            signInError = "Honeywell no longer accepts the saved password. Sign in again."
            phase = .signedOut
        case .locked(let until):
            phase = .locked(until: until)
        case .network:
            trouble = .offline
            failures += 1
        default:
            trouble = .unavailable
            failures += 1
        }
    }

    public func adjust(_ id: Int, by steps: Int) {
        guard canControl, let shown = thermostats.first(where: { $0.id == id }), shown.isOnline, let which = shown.activeSetpoint,
              let current = shown.setpoint(which), let limits = shown.range(which) else { return }
        let value = min(max(current + Double(steps) * shown.units.step, limits.lowerBound), limits.upperBound)
        guard value != current else { return }
        pending[id] = Pending(which: which, value: value)
        sends[id]?.cancel()
        sends[id] = Task { [debounce] in
            do { try await Task.sleep(for: debounce) } catch { return }
            await self.commit(id)
        }
    }

    private func commit(_ id: Int) async {
        guard let wanted = pending[id] else { return }
        let kind = holdKind
        await perform(id) { try $0.setpointChange(wanted.which, to: wanted.value, hold: kind) }
        if pending[id] == wanted { pending[id] = nil }
        await refresh()
    }

    public func setMode(_ id: Int, to mode: TccMode) async {
        await perform(id) { try $0.modeChange(mode) }
        await refresh()
    }

    public func resumeSchedule(_ id: Int) async {
        await perform(id) { $0.resumeChange() }
        await refresh()
    }

    private func perform(_ id: Int, _ build: (TccThermostat) throws -> TccChange) async {
        guard canControl, let before = readings.first(where: { $0.id == id }) else { return }
        do {
            let change = try build(before)
            guard change != TccChange(deviceId: id) else { return }
            if let index = readings.firstIndex(where: { $0.id == id }) { readings[index].apply(change) }
            try await client.apply(change)
        } catch {
            if let index = readings.firstIndex(where: { $0.id == id }) { readings[index] = before }
            let failure = error as? TccError ?? .unexpectedResponse
            if case .locked(let until) = failure { phase = .locked(until: until) }
            if failure != .cancelled { notice = failure.userMessage }
        }
    }

    private static func signInMessage(_ error: Error) -> String {
        switch error as? TccError ?? .unexpectedResponse {
        case .locked(let until):
            return "Honeywell has paused sign-in after too many attempts. This also blocks the Total Connect Comfort app. Try again after \(until.formatted(date: .omitted, time: .shortened))."
        case let failure:
            return failure.userMessage
        }
    }
}
