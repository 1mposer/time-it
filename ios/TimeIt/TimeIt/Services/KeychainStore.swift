import Foundation
import Security

/// The real Keychain (ADR-0001): a generic-password item per key, so the
/// install UUID survives reinstall. Service string is deliberately NOT the
/// bundle id — the pending com.timeit.app.dev rename (ROADMAP item 4) must
/// not strand the install id under the old name.
struct KeychainStore: KeychainStoring {

    private static let service = "com.timeit.device"

    func read(key: String) -> String? {
        var query = Self.baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func write(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let base = Self.baseQuery(for: key)
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        // Readable after the first unlock (add-time only — an accessibility
        // attribute in the copy-matching query would mismatch existing
        // items): a protection-class miss at a locked-state launch re-mints
        // the UUID, and a duplicate device row means duplicate pushes.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess || read(key: key) != value {
            // One retry covers a transient duplicate-item race; beyond that
            // the failure is accepted residual risk — this session keeps its
            // minted id and the next launch re-mints.
            SecItemDelete(base as CFDictionary)
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func baseQuery(for key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
}
