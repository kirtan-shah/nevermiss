import Foundation
import Security

// MARK: - Type Definition

actor KeychainService {

    // MARK: - Static Properties

    static let shared = KeychainService()

    // MARK: - Properties

    private let service = "codes.maker.NeverMiss"

    // MARK: - Actions/Methods

    func save(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(newItem as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func retrieve(for key: Key) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.readFailed(status)
        }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        return string
    }

    func delete(for key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    func deleteAll() throws {
        for key in [Key.googleAccessToken, Key.googleRefreshToken, Key.googleTokenExpiry] {
            try delete(for: key)
        }
    }

    func saveGoogleTokens(accessToken: String, refreshToken: String?, expiryDate: Date) throws {
        try save(accessToken, for: .googleAccessToken)
        if let refreshToken = refreshToken {
            try save(refreshToken, for: .googleRefreshToken)
        }
        let expiryString = String(expiryDate.timeIntervalSince1970)
        try save(expiryString, for: .googleTokenExpiry)
    }

    func getGoogleAccessToken() throws -> String? {
        try retrieve(for: .googleAccessToken)
    }

    func getGoogleRefreshToken() throws -> String? {
        try retrieve(for: .googleRefreshToken)
    }

    func getGoogleTokenExpiry() throws -> Date? {
        guard let expiryString = try retrieve(for: .googleTokenExpiry),
              let interval = TimeInterval(expiryString) else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    func hasGoogleTokens() -> Bool {
        do {
            return try retrieve(for: .googleRefreshToken) != nil
        } catch {
            return false
        }
    }

    func clearGoogleTokens() throws {
        try delete(for: .googleAccessToken)
        try delete(for: .googleRefreshToken)
        try delete(for: .googleTokenExpiry)
    }
}

// MARK: - Supporting Types

extension KeychainService {
    enum Key: String {
        case googleAccessToken = "google_access_token"
        case googleRefreshToken = "google_refresh_token"
        case googleTokenExpiry = "google_token_expiry"
    }

    enum KeychainError: Error, LocalizedError {
        case saveFailed(OSStatus)
        case readFailed(OSStatus)
        case deleteFailed(OSStatus)
        case dataConversionFailed
        case itemNotFound

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                return "Failed to save to Keychain: \(status)"
            case .readFailed(let status):
                return "Failed to read from Keychain: \(status)"
            case .deleteFailed(let status):
                return "Failed to delete from Keychain: \(status)"
            case .dataConversionFailed:
                return "Failed to convert data"
            case .itemNotFound:
                return "Item not found in Keychain"
            }
        }
    }
}
