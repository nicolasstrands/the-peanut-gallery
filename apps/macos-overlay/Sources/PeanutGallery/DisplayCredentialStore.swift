import Foundation
import Security

/// Read-only display credentials are scoped to both endpoint and room. Keeping
/// them in Keychain avoids exposing them in ordinary preferences or audience URLs.
enum DisplayCredentialStore {
    private static let service = "com.peanutgallery.overlay.display"

    private static func query(room: String, server: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(server)|\(room)",
        ]
    }

    static func load(room: String, server: String) -> String? {
        var query = query(room: room, server: server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String, room: String, server: String) {
        let query = query(room: room, server: server)
        let value = [kSecValueData as String: Data(token.utf8)]
        let result = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if result == errSecItemNotFound {
            var item = query.merging(value) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
