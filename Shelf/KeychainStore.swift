import Foundation
import Security

struct StoredSession: Codable, Equatable {
    var serverURL: String
    var username: String
    var password: String
    var token: String
    var refreshToken: String
    var apiKey: String
    var deviceId: String
    var kavitaVersion: String?
}

enum KeychainStore {
    private static let service = "com.kiefermenard.shelf"
    private static let account = "kavita-session"

    static func load() throws -> StoredSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError(status: status)
        }
        return try JSONDecoder().decode(StoredSession.self, from: data)
    }

    static func save(_ session: StoredSession) throws {
        let data = try JSONEncoder().encode(session)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let existing = SecItemCopyMatching(baseQuery as CFDictionary, nil)
        if existing == errSecSuccess {
            let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
            return
        }
        if existing != errSecItemNotFound {
            throw KeychainError(status: existing)
        }
        var insert = baseQuery
        attributes.forEach { insert[$0.key] = $0.value }
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct KeychainError: Error, LocalizedError {
    var status: OSStatus

    var errorDescription: String? {
        "The Keychain could not store this Kavita session (status \(status))."
    }
}
