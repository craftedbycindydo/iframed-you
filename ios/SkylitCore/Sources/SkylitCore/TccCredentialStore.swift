import Foundation
import Security

public struct TccCredentials: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    public var description: String { "TccCredentials(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

public protocol TccCredentialStoring: Sendable {
    func load() -> TccCredentials?
    func save(_ credentials: TccCredentials)
    func clear()
}

public struct TccCredentialStore: TccCredentialStoring {
    private let service: String

    public init(service: String = "com.iframed.you.tcc") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "account",
         kSecAttrSynchronizable as String: false]
    }

    public func load() -> TccCredentials? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return nil }
        return try? JSONDecoder().decode(TccCredentials.self, from: data)
    }

    public func save(_ credentials: TccCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    public func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

public final class InMemoryTccCredentialStore: TccCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: TccCredentials?

    public init(_ stored: TccCredentials? = nil) {
        self.stored = stored
    }

    public func load() -> TccCredentials? {
        lock.withLock { stored }
    }

    public func save(_ credentials: TccCredentials) {
        lock.withLock { stored = credentials }
    }

    public func clear() {
        lock.withLock { stored = nil }
    }
}
