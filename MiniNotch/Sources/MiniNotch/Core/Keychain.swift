import Foundation
import Security

// ============================================================
// Keychain —— 敏感凭据（邮箱应用密码等）存系统钥匙串，
// 不落明文 settings.json（email-message-reminders design D7）。
// ============================================================

enum Keychain {
    private static let service = "com.mininotch.app"

    /// 写入（已存在则覆盖）；空串等价于删除
    static func save(_ value: String, account: String) {
        guard !value.isEmpty else { delete(account: account); return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess { NSLog("[Keychain] save \(account) failed: \(status)") }
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
