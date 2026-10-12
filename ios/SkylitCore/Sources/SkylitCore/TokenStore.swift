import Foundation
import Security

public struct FrameCredential: Codable, Equatable, Sendable {
    public let token: String
    public let fp: String

    public var frameId: String { Pin.frameId(for: fp) }
    public var isValid: Bool { Pin.isValid(fp) && Hex.isValid(token, bytes: 32) }

    public init(token: String, fp: String) {
        self.token = token
        self.fp = fp
    }
}

public protocol TokenStoring: Sendable {
    func credential(for frameId: String) -> FrameCredential?
    func save(_ credential: FrameCredential)
    func remove(for frameId: String)
    func removeLegacy() -> Bool
}

public struct KeychainTokenStore: TokenStoring {
    private let service: String

    public init(service: String = "com.iframed.you.frame-token") {
        self.service = service
    }

    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrSynchronizable as String: false]
    }

    private func query(_ frameId: String) -> [String: Any] {
        base.merging([kSecAttrAccount as String: frameId]) { _, new in new }
    }

    public func credential(for frameId: String) -> FrameCredential? {
        var lookup = query(frameId)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &found) == errSecSuccess, let data = found as? Data,
              let credential = try? JSONDecoder().decode(FrameCredential.self, from: data),
              credential.isValid, credential.frameId == frameId else { return nil }
        return credential
    }

    public func save(_ credential: FrameCredential) {
        guard credential.isValid, let data = try? JSONEncoder().encode(credential) else { return }
        SecItemDelete(query(credential.frameId) as CFDictionary)
        var item = query(credential.frameId)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    public func remove(for frameId: String) {
        SecItemDelete(query(frameId) as CFDictionary)
    }

    public func removeLegacy() -> Bool {
        var lookup = base
        lookup[kSecReturnAttributes as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitAll
        var found: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &found) == errSecSuccess, let items = found as? [[String: Any]] else { return false }
        let stale = items.compactMap { $0[kSecAttrAccount as String] as? String }.filter { credential(for: $0) == nil }
        stale.forEach(remove)
        return !stale.isEmpty
    }
}

public final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: [String: FrameCredential] = [:]
    private var legacy: [String: String]

    public init(legacy: [String: String] = [:]) {
        self.legacy = legacy
    }

    public var legacyTokens: [String: String] {
        lock.withLock { legacy }
    }

    public func credential(for frameId: String) -> FrameCredential? {
        lock.withLock { credentials[frameId] }
    }

    public func save(_ credential: FrameCredential) {
        guard credential.isValid else { return }
        lock.withLock { credentials[credential.frameId] = credential }
    }

    public func remove(for frameId: String) {
        lock.withLock { credentials[frameId] = nil }
    }

    public func removeLegacy() -> Bool {
        lock.withLock {
            defer { legacy = [:] }
            return !legacy.isEmpty
        }
    }
}

public struct PairedFrame: Codable, Equatable, Sendable {
    public let frameId: String
    public var name: String

    public init(frameId: String, name: String) {
        self.frameId = frameId
        self.name = name
    }
}

public struct PairedFrameStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "skylit.pairedFrame"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var current: PairedFrame? {
        get { defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(PairedFrame.self, from: $0) } }
        nonmutating set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

public struct DeviceNameStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let fallback: String
    private let key = "skylit.deviceName"

    public init(defaults: UserDefaults = .standard, fallback: String = "iPhone") {
        self.defaults = defaults
        self.fallback = fallback
    }

    public var name: String {
        get { defaults.string(forKey: key).flatMap(Limits.cleanDeviceName) ?? Limits.cleanDeviceName(fallback) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: key) }
    }
}
