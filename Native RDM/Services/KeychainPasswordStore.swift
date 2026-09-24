import Foundation
import Security

nonisolated enum KeychainPasswordStore {
    private static let service = "com.yion.NativeRDM.redis-password"

    static func password(for id: UUID) -> String {
        var query: [String: Any] = baseQuery(for: id)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func setPassword(_ password: String, for id: UUID) throws {
        deletePassword(for: id)
        let trimmed = password
        guard !trimmed.isEmpty else { return }

        var query = baseQuery(for: id)
        query[kSecValueData as String] = Data(trimmed.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ValidationError("无法保存密码（Keychain \(status)）")
        }
    }

    static func deletePassword(for id: UUID) {
        SecItemDelete(baseQuery(for: id) as CFDictionary)
    }

    private static func baseQuery(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
    }
}
