import Foundation
import Security

enum AskSecrets {
    private static let service = "com.burbank.yourmark"
    private static let account = "ask-api-key"

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return "" }
        let value = String(data: data, encoding: .utf8) ?? ""
        if !value.isEmpty {
            migrateAccess(value)
        }
        return value
    }

    static func save(_ value: String) {
        delete()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        var item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrLabel as String: "yourMark Ask key",
        ]
        if let access = openAccess() {
            item[kSecAttrAccess as String] = access
        }
        SecItemAdd(item as CFDictionary, nil)
        UserDefaults.standard.set(true, forKey: "askKeyACLOpen")
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.set(false, forKey: "askKeyACLOpen")
    }

    /// Default Keychain ACL is "this exact binary". Ad-hoc signatures change
    /// every yourMark version, so the login-keychain dialog comes back.
    /// Relax decrypt/encrypt to any app on this Mac (the item still lives in
    /// the locked login keychain). Developer ID signing will make this moot.
    private static func openAccess() -> SecAccess? {
        var access: SecAccess?
        guard SecAccessCreate("yourMark Ask key" as CFString, nil, &access) == errSecSuccess,
              let access else { return nil }
        var cfList: CFArray?
        guard SecAccessCopyACLList(access, &cfList) == errSecSuccess else { return access }
        let raw = (cfList as? [Any]) ?? []
        for case let acl as SecACL in raw {
            let auths = (SecACLCopyAuthorizations(acl) as? [String]) ?? []
            if auths.contains(where: isOwnerACL) { continue }
            var apps: CFArray?
            var desc: CFString?
            var selector = SecKeychainPromptSelector()
            guard SecACLCopyContents(acl, &apps, &desc, &selector) == errSecSuccess else { continue }
            var sel = SecKeychainPromptSelector()
            let text = (desc as String?) ?? "yourMark Ask key"
            _ = SecACLSetContents(acl, nil, text as CFString, &sel)
        }
        return access
    }

    private static func isOwnerACL(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("changeacl") || n.contains("changeowner") || n.contains("acl") && n.contains("change")
    }

    /// Rewrite an item created by an older build, once we already have access.
    private static func migrateAccess(_ value: String) {
        if UserDefaults.standard.bool(forKey: "askKeyACLOpen") { return }
        save(value)
    }
}
