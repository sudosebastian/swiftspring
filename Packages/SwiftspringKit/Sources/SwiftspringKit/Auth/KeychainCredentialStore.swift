import Foundation
import Security

public enum KeychainError: Error, LocalizedError, Sendable {
    case unexpectedStatus(OSStatus)
    case dataConversionFailed
    case itemNotFound

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain error: \(status)"
        case .dataConversionFailed:
            return "Could not convert keychain data."
        case .itemNotFound:
            return "Credential not found in Keychain."
        }
    }
}

public struct AccountCredentials: Codable, Sendable, Equatable {
    public var password: String?
    public var refreshToken: String?
    public var accessToken: String?
    public var accessTokenExpiresAt: Date?
    public var oauthClientId: String?

    public init(
        password: String? = nil,
        refreshToken: String? = nil,
        accessToken: String? = nil,
        accessTokenExpiresAt: Date? = nil,
        oauthClientId: String? = nil
    ) {
        self.password = password
        self.refreshToken = refreshToken
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.oauthClientId = oauthClientId
    }
}

public protocol CredentialStore: Sendable {
    func save(accountId: EntityID, credentials: AccountCredentials) throws
    func load(accountId: EntityID) throws -> AccountCredentials?
    func delete(accountId: EntityID) throws
}

public struct KeychainCredentialStore: CredentialStore {
    public let service: String

    public init(service: String = "com.swiftspring.credentials") {
        self.service = service
    }

    public func save(accountId: EntityID, credentials: AccountCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountId.rawValue,
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func load(accountId: EntityID) throws -> AccountCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountId.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = item as? Data else {
            throw KeychainError.dataConversionFailed
        }
        return try JSONDecoder().decode(AccountCredentials.self, from: data)
    }

    public func delete(accountId: EntityID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountId.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

/// In-memory store for unit tests and Linux-less previews.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: AccountCredentials] = [:]

    public init() {}

    public func save(accountId: EntityID, credentials: AccountCredentials) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[accountId.rawValue] = credentials
    }

    public func load(accountId: EntityID) throws -> AccountCredentials? {
        lock.lock()
        defer { lock.unlock() }
        return storage[accountId.rawValue]
    }

    public func delete(accountId: EntityID) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: accountId.rawValue)
    }
}
