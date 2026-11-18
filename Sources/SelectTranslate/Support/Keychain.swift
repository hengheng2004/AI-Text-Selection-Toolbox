import Foundation
import Security

/// API Key 存放位置。
///
/// 优先用 Data Protection 钥匙串：它按 App 签名授权，**不会**弹
/// “xxx 想要访问钥匙串中的机密信息”那种 ACL 对话框。
/// 如果系统拒绝（例如签名环境不支持），退回仅本人可读的 0600 文件。
///
/// 旧版本把 Key 存在登录钥匙串的 ACL 条目里，一旦重新签名就会触发授权弹窗
/// 并卡住主线程，这里不再读取它。
enum Keychain {
    private static let service = "com.local.selecttranslate"
    private static let account = "llm-api-key"

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("SelectTranslate/api-key", isDirectory: false)
    }

    // MARK: - 读写

    static func load() -> String? {
        if let value = loadFromModernKeychain(), !value.isEmpty { return value }
        if let value = loadFromFile(), !value.isEmpty { return value }
        return nil
    }

    static func save(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            delete()
            return
        }
        if saveToModernKeychain(trimmed) {
            removeFile()
        } else {
            saveToFile(trimmed)
        }
    }

    static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
        removeFile()
    }

    /// 不读取内容，只用于日志/诊断
    static func backendDescription() -> String {
        loadFromModernKeychain() != nil ? "data-protection-keychain" : (loadFromFile() != nil ? "file" : "empty")
    }

    // MARK: - Data Protection 钥匙串

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
    }

    private static func loadFromModernKeychain() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveToModernKeychain(_ value: String) -> Bool {
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery()
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    // MARK: - 文件兜底

    private static func loadFromFile() -> String? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveToFile(_ value: String) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? Data(value.utf8).write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func removeFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}