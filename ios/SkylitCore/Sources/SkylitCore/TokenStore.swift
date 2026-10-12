import Foundation
import Security

public protocol TokenStoring: Sendable {
    func token(for frameId: String) -> String?
    func save(_ token: String, for frameId: String)
    func removeToken(for frameId: String)
}

public struct KeychainTokenStore: TokenStoring {
    private let service: String

    public init(service: String = "com.iframed.you.frame-token") {
        self.service = service
    }

    private func query(_ frameId: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: frameId]
    }

    public func token(for frameId: String) -> String? {
        var lookup = query(frameId)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ token: String, for frameId: String) {
        SecItemDelete(query(frameId) as CFDictionary)
        var item = query(frameId)
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    public func removeToken(for frameId: String) {
        SecItemDelete(query(frameId) as CFDictionary)
    }
}

public final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String: String]

    public init(_ tokens: [String: String] = [:]) {
        self.tokens = tokens
    }

    public func token(for frameId: String) -> String? {
        lock.withLock { tokens[frameId] }
    }

    public func save(_ token: String, for frameId: String) {
        lock.withLock { tokens[frameId] = token }
    }

    public func removeToken(for frameId: String) {
        lock.withLock { tokens[frameId] = nil }
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
