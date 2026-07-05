import Foundation
import Security

// MARK: - SyncConfig (P2)
// The device's sync pairing: where the backend is + the capability key. The syncKey is a
// SECRET (256-bit bearer capability) → Keychain. backendUrl + anonKey are publishable by
// design (the anon key is meant to ship in clients) → UserDefaults. `enabled` gates the loop
// so the app stays purely local until the user opts in.
struct SyncConfig: Equatable {
    var backendUrl: String
    var anonKey: String
    var syncKey: String
    var enabled: Bool

    /// A valid sync key is exactly a 43-char base64url string (256-bit key, no padding).
    /// This MUST be enforced before enabling sync: deriveOwnerId("") is a constant hash, so a
    /// blank/short key would dump every user into ONE shared bucket (cross-user data leak).
    static func isValidSyncKey(_ k: String) -> Bool {
        guard k.count == 43 else { return false }
        return k.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// Ready to actually sync: enabled, a parseable URL, a non-empty anon key, a valid sync key.
    var isSyncable: Bool {
        enabled && URL(string: backendUrl) != nil && !anonKey.isEmpty && Self.isValidSyncKey(syncKey)
    }
}

// MARK: - Persistence
enum SyncConfigStore {
    private static let dURL = "buddy.sync.backendUrl"
    private static let dAnon = "buddy.sync.anonKey"
    private static let dEnabled = "buddy.sync.enabled"
    private static let keychainAccount = "buddy.sync.syncKey"

    static func load() -> SyncConfig {
        let d = UserDefaults.standard
        return SyncConfig(
            backendUrl: d.string(forKey: dURL) ?? "",
            anonKey:    d.string(forKey: dAnon) ?? "",
            syncKey:    Keychain.get(keychainAccount) ?? "",
            enabled:    d.bool(forKey: dEnabled))
    }

    /// Persist. Rejects an enabled config with an invalid key (fail-closed) — returns false so the
    /// UI can surface it, and never writes `enabled:true` with a bad key.
    @discardableResult
    static func save(_ cfg: SyncConfig) -> Bool {
        if cfg.enabled && !cfg.isSyncable { return false }
        let d = UserDefaults.standard
        d.set(cfg.backendUrl, forKey: dURL)
        d.set(cfg.anonKey, forKey: dAnon)
        d.set(cfg.enabled, forKey: dEnabled)
        if cfg.syncKey.isEmpty { Keychain.delete(keychainAccount) }
        else { Keychain.set(cfg.syncKey, account: keychainAccount) }
        return true
    }

    static func clear() {
        let d = UserDefaults.standard
        [dURL, dAnon, dEnabled].forEach { d.removeObject(forKey: $0) }
        Keychain.delete(keychainAccount)
    }
}

// MARK: - Keychain (minimal string store)
enum Keychain {
    private static let service = "fyi.whale.buddy.sync"

    static func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}
