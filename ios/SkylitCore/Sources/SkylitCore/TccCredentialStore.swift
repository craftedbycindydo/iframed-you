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

public struct TccSession: Codable, Equatable, Sendable {
    public var cookies: [String: String]
    public var lastLogin: Date?

    public init(cookies: [String: String], lastLogin: Date?) {
        self.cookies = cookies
        self.lastLogin = lastLogin
    }
}

public protocol TccCredentialStoring: Sendable {
    func load() -> TccCredentials?
    func save(_ credentials: TccCredentials)
    func clear()
    func loadSession() -> TccSession?
    func saveSession(_ session: TccSession?)
}

public struct TccCredentialStore: TccCredentialStoring {
    private let service: String

    public init(service: String = "com.iframed.you.tcc") {
        self.service = service
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    private func read<T: Decodable>(_ account: String, as type: T.Type) -> T? {
        var lookup = query(account)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ account: String, _ value: T?) {
        SecItemDelete(query(account) as CFDictionary)
        guard let value, let data = try? JSONEncoder().encode(value) else { return }
        var item = query(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    public func load() -> TccCredentials? {
        read("account", as: TccCredentials.self)
    }

    public func save(_ credentials: TccCredentials) {
        write("account", credentials)
    }

    public func clear() {
        write("account", Optional<TccCredentials>.none)
        saveSession(nil)
    }

    public func loadSession() -> TccSession? {
        read("session", as: TccSession.self)
    }

    public func saveSession(_ session: TccSession?) {
        write("session", session)
    }
}

public final class InMemoryTccCredentialStore: TccCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: TccCredentials?
    private var session: TccSession?

    public init(_ stored: TccCredentials? = nil) {
        self.stored = stored
    }

    public func loadSession() -> TccSession? {
        lock.withLock { session }
    }

    public func saveSession(_ session: TccSession?) {
        lock.withLock { self.session = session }
    }

    public func load() -> TccCredentials? {
        lock.withLock { stored }
    }

    public func save(_ credentials: TccCredentials) {
        lock.withLock { stored = credentials }
    }

    public func clear() {
        lock.withLock {
            stored = nil
            session = nil
        }
    }
}
