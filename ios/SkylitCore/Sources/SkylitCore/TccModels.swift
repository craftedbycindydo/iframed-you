import Foundation

public enum TccError: Error, Equatable, Sendable {
    case needsSignIn
    case badCredentials
    case loginFailed
    case locked(until: Date)
    case sessionExpired
    case unavailable(status: Int)
    case unexpectedResponse
    case network
    case cancelled
    case rejected
    case outOfRange
    case notAllowed
    case foreignHost
    case tooLarge

    public var userMessage: String {
        switch self {
        case .needsSignIn:
            return "Sign in to Total Connect Comfort to see your thermostats."
        case .badCredentials:
            return "Honeywell didn't accept that email and password."
        case .loginFailed:
            return "Honeywell didn't complete the sign-in. Its service may be down; try again later."
        case .locked:
            return "Honeywell has paused sign-in after too many attempts. Try again later."
        case .sessionExpired:
            return "Honeywell ended the session. Signing in again shortly."
        case .unavailable, .unexpectedResponse, .tooLarge, .foreignHost:
            return "Honeywell isn't answering properly right now."
        case .network:
            return "Can't reach Honeywell. Check your connection."
        case .cancelled:
            return "Cancelled."
        case .rejected:
            return "The thermostat didn't accept that change."
        case .outOfRange:
            return "That is outside the range the thermostat allows."
        case .notAllowed:
            return "This thermostat doesn't allow that."
        }
    }
}

public enum TccUnits: String, Sendable, Equatable {
    case fahrenheit = "F"
    case celsius = "C"

    public var step: Double { self == .celsius ? 0.5 : 1 }
}

public enum TccMode: String, Sendable, Equatable, CaseIterable {
    case emergencyHeat
    case heat
    case off
    case cool
    case auto

    public init?(switchPosition: Int) {
        switch switchPosition {
        case 0: self = .emergencyHeat
        case 1: self = .heat
        case 2: self = .off
        case 3: self = .cool
        case 4, 5: self = .auto
        default: return nil
        }
    }

    public var switchPosition: Int {
        switch self {
        case .emergencyHeat: return 0
        case .heat: return 1
        case .off: return 2
        case .cool: return 3
        case .auto: return 4
        }
    }

    var allowedKey: String {
        switch self {
        case .emergencyHeat: return "SwitchEmergencyHeatAllowed"
        case .heat: return "SwitchHeatAllowed"
        case .off: return "SwitchOffAllowed"
        case .cool: return "SwitchCoolAllowed"
        case .auto: return "SwitchAutoAllowed"
        }
    }
}

public enum TccSetpoint: String, Sendable, Equatable {
    case heat
    case cool
}

public enum TccHoldStatus: Int, Sendable, Equatable {
    case schedule = 0
    case temporary = 1
    case permanent = 2
}

public enum TccHold: Sendable, Equatable {
    case schedule
    case temporary(untilMinutes: Int?)
    case permanent
}

public enum TccHoldKind: Sendable, Equatable {
    case untilNextPeriod
    case permanent
}

public enum TccFanMode: Int, Sendable, Equatable {
    case auto = 0
    case on = 1
    case circulate = 2
    case followSchedule = 3
}

public enum TccRunning: Int, Sendable, Equatable {
    case idle = 0
    case heating = 1
    case cooling = 2
}

public struct TccDevice: Equatable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let macId: String?

    public init(id: Int, name: String, macId: String? = nil) {
        self.id = id
        self.name = name
        self.macId = macId
    }
}

public struct TccLocation: Equatable, Sendable, Identifiable {
    public let id: Int
    public let devices: [TccDevice]

    init?(_ raw: [String: Any]) {
        guard let id = (raw["LocationID"] as? NSNumber)?.intValue else { return nil }
        self.id = id
        devices = (raw["Devices"] as? [[String: Any]] ?? []).compactMap { device in
            guard let deviceId = (device["DeviceID"] as? NSNumber)?.intValue else { return nil }
            return TccDevice(id: deviceId, name: device["Name"] as? String ?? "Thermostat", macId: device["MacID"] as? String)
        }
    }
}

public struct TccThermostat: Equatable, Sendable, Identifiable {
    public let id: Int
    public var name: String
    public var isOnline: Bool
    public var units: TccUnits
    public var indoorTemperature: Double?
    public var indoorHumidity: Double?
    public var outdoorTemperature: Double?
    public var outdoorHumidity: Double?
    public var heatSetpoint: Double?
    public var coolSetpoint: Double?
    public var heatRange: ClosedRange<Double>?
    public var coolRange: ClosedRange<Double>?
    public var deadband: Double
    public var mode: TccMode?
    public var allowedModes: Set<TccMode>
    public var heatHold: TccHoldStatus?
    public var coolHold: TccHoldStatus?
    public var heatNextPeriod: Int?
    public var coolNextPeriod: Int?
    public var fanMode: TccFanMode?
    public var isFanRunning: Bool
    public var running: TccRunning?

    public init(device: TccDevice, payload: [String: Any]) {
        let latest = payload["latestData"] as? [String: Any] ?? [:]
        let ui = latest["uiData"] as? [String: Any] ?? [:]
        let fan = latest["fanData"] as? [String: Any] ?? [:]
        func number(_ key: String) -> Double? {
            guard let value = ui[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            return value.doubleValue
        }
        func whole(_ key: String, in source: [String: Any]) -> Int? {
            guard let value = source[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            return value.intValue
        }
        func flag(_ key: String, in source: [String: Any]) -> Bool {
            source[key] as? Bool ?? false
        }
        func range(_ lower: String, _ upper: String) -> ClosedRange<Double>? {
            guard let low = number(lower), let high = number(upper), low <= high else { return nil }
            return low...high
        }
        id = device.id
        name = device.name
        isOnline = flag("deviceLive", in: payload) && !flag("communicationLost", in: payload)
        units = TccUnits(rawValue: ui["DisplayUnits"] as? String ?? "") ?? .fahrenheit
        indoorTemperature = number("DispTemperature")
        indoorHumidity = flag("IndoorHumiditySensorAvailable", in: ui) && flag("IndoorHumiditySensorNotFault", in: ui) ? number("IndoorHumidity") : nil
        outdoorTemperature = flag("OutdoorTemperatureAvailable", in: ui) ? number("OutdoorTemperature") : nil
        outdoorHumidity = flag("OutdoorHumidityAvailable", in: ui) ? number("OutdoorHumidity") : nil
        heatSetpoint = number("HeatSetpoint")
        coolSetpoint = number("CoolSetpoint")
        heatRange = range("HeatLowerSetptLimit", "HeatUpperSetptLimit")
        coolRange = range("CoolLowerSetptLimit", "CoolUpperSetptLimit")
        deadband = number("Deadband") ?? 0
        mode = whole("SystemSwitchPosition", in: ui).flatMap(TccMode.init(switchPosition:))
        allowedModes = Set(TccMode.allCases.filter { flag($0.allowedKey, in: ui) })
        heatHold = whole("StatusHeat", in: ui).flatMap(TccHoldStatus.init(rawValue:))
        coolHold = whole("StatusCool", in: ui).flatMap(TccHoldStatus.init(rawValue:))
        heatNextPeriod = whole("HeatNextPeriod", in: ui)
        coolNextPeriod = whole("CoolNextPeriod", in: ui)
        let hasFan = flag("hasFan", in: latest)
        fanMode = hasFan ? whole("fanMode", in: fan).flatMap(TccFanMode.init(rawValue:)) : nil
        isFanRunning = hasFan && flag("fanIsRunning", in: fan)
        running = whole("EquipmentOutputStatus", in: ui).flatMap(TccRunning.init(rawValue:))
    }

    public var activeSetpoint: TccSetpoint? {
        switch mode {
        case .heat, .emergencyHeat: return .heat
        case .cool: return .cool
        default: return nil
        }
    }

    public func setpoint(_ which: TccSetpoint) -> Double? {
        which == .heat ? heatSetpoint : coolSetpoint
    }

    public func range(_ which: TccSetpoint) -> ClosedRange<Double>? {
        which == .heat ? heatRange : coolRange
    }

    public var hold: TccHold? {
        let cooling = activeSetpoint == .cool
        guard let status = cooling ? coolHold : heatHold else { return nil }
        switch status {
        case .schedule: return .schedule
        case .permanent: return .permanent
        case .temporary:
            let period = cooling ? coolNextPeriod : heatNextPeriod
            return .temporary(untilMinutes: period.flatMap { (0..<96).contains($0) ? $0 * 15 : nil })
        }
    }

    public var canSwitchHeatCool: Bool {
        allowedModes.contains(.heat) && allowedModes.contains(.cool)
    }

    public func setpointChange(_ which: TccSetpoint, to value: Double, hold kind: TccHoldKind = .untilNextPeriod) throws -> TccChange {
        guard let limits = range(which), let heat = heatSetpoint, let cool = coolSetpoint else { throw TccError.notAllowed }
        guard limits.contains(value) else { throw TccError.outOfRange }
        var change = TccChange(deviceId: id)
        var newHeat = heat
        var newCool = cool
        switch which {
        case .heat:
            newHeat = value
            if deadband > 0, cool - deadband <= value { newCool = value + deadband }
        case .cool:
            newCool = value
            if deadband > 0, heat + deadband >= value { newHeat = value - deadband }
        }
        if newCool != cool, coolRange?.contains(newCool) == false { throw TccError.outOfRange }
        if newHeat != heat, heatRange?.contains(newHeat) == false { throw TccError.outOfRange }
        change.heatSetpoint = newHeat
        change.coolSetpoint = newCool
        switch kind {
        case .permanent:
            change.statusHeat = TccHoldStatus.permanent.rawValue
            change.statusCool = TccHoldStatus.permanent.rawValue
        case .untilNextPeriod:
            if heatHold == .schedule, coolHold == .schedule {
                change.statusHeat = TccHoldStatus.temporary.rawValue
                change.statusCool = TccHoldStatus.temporary.rawValue
                let period = which == .heat ? heatNextPeriod : coolNextPeriod
                change.heatNextPeriod = period
                change.coolNextPeriod = period
            }
        }
        return change
    }

    public func modeChange(_ target: TccMode) throws -> TccChange {
        guard target == .heat || target == .cool, allowedModes.contains(target) else { throw TccError.notAllowed }
        var change = TccChange(deviceId: id)
        change.systemSwitch = target.switchPosition
        return change
    }

    public func resumeChange() -> TccChange {
        var change = TccChange(deviceId: id)
        change.statusHeat = TccHoldStatus.schedule.rawValue
        change.statusCool = TccHoldStatus.schedule.rawValue
        return change
    }

    public mutating func apply(_ change: TccChange) {
        if let value = change.heatSetpoint { heatSetpoint = value }
        if let value = change.coolSetpoint { coolSetpoint = value }
        if let value = change.statusHeat { heatHold = TccHoldStatus(rawValue: value) }
        if let value = change.statusCool { coolHold = TccHoldStatus(rawValue: value) }
        if let value = change.heatNextPeriod { heatNextPeriod = value }
        if let value = change.coolNextPeriod { coolNextPeriod = value }
        if let value = change.systemSwitch { mode = TccMode(switchPosition: value) }
    }
}

public struct TccChange: Equatable, Sendable, Encodable {
    public var deviceId: Int
    public var systemSwitch: Int?
    public var heatSetpoint: Double?
    public var coolSetpoint: Double?
    public var heatNextPeriod: Int?
    public var coolNextPeriod: Int?
    public var statusHeat: Int?
    public var statusCool: Int?
    public var fanMode: Int?

    public init(deviceId: Int) {
        self.deviceId = deviceId
    }

    private enum CodingKeys: String, CodingKey {
        case deviceId = "DeviceID"
        case systemSwitch = "SystemSwitch"
        case heatSetpoint = "HeatSetpoint"
        case coolSetpoint = "CoolSetpoint"
        case heatNextPeriod = "HeatNextPeriod"
        case coolNextPeriod = "CoolNextPeriod"
        case statusHeat = "StatusHeat"
        case statusCool = "StatusCool"
        case fanMode = "FanMode"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(systemSwitch, forKey: .systemSwitch)
        try container.encode(heatSetpoint, forKey: .heatSetpoint)
        try container.encode(coolSetpoint, forKey: .coolSetpoint)
        try container.encode(heatNextPeriod, forKey: .heatNextPeriod)
        try container.encode(coolNextPeriod, forKey: .coolNextPeriod)
        try container.encode(statusHeat, forKey: .statusHeat)
        try container.encode(statusCool, forKey: .statusCool)
        try container.encode(fanMode, forKey: .fanMode)
    }
}

public struct TccLoginGuard: Codable, Equatable, Sendable {
    public var failures = 0
    public var lockedUntil: Date?

    public init() {}
}

public enum TccBackoff {
    public static func delay(failures: Int, base: TimeInterval = 60, cap: TimeInterval = 600) -> TimeInterval {
        min(cap, base * pow(2, Double(min(max(failures, 0), 10))))
    }

    public static func lock(failures: Int, threshold: Int = 3, base: TimeInterval = 600, cap: TimeInterval = 21600) -> TimeInterval? {
        failures < threshold ? nil : min(cap, base * pow(2, Double(min(failures - threshold, 10))))
    }
}
