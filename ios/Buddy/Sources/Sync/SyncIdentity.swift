import Foundation
import CryptoKit

// MARK: - SyncIdentity (QR pairing core) — Swift mirror of dist/index.html.
//
// A high-entropy capability key is generated once and shared device-to-device by QR.
// The DB row key (owner_id) is derived as sha256(syncKey) so the raw secret is never
// the literal row id. Both devices derive the SAME owner_id from the same key — pinned
// by a shared test vector (sha256("buddy-test-key")) asserted in both test suites.
enum SyncIdentity {

    /// 256-bit capability key, base64url (43 chars, no padding) — matches generateSyncKey() in JS.
    static func generateKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// owner_id = lowercase hex of sha256(syncKey utf8) — identical to deriveOwnerId() in JS.
    static func ownerId(for syncKey: String) -> String {
        SHA256.hash(data: Data(syncKey.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // The QR payload carries everything the phone needs to sync: where the backend is
    // (backendUrl), how to authenticate (anonKey — publishable by design, safe to embed),
    // and the capability key (syncKey). Mac and iOS MUST agree on these JSON keys.
    struct Pairing: Codable, Equatable { var v: Int = 1; var backendUrl: String; var anonKey: String; var syncKey: String }

    /// The QR payload: {v, backendUrl, anonKey, syncKey} JSON.
    static func payload(backendUrl: String, anonKey: String, syncKey: String) -> String {
        let p = Pairing(backendUrl: backendUrl, anonKey: anonKey, syncKey: syncKey)
        return (try? String(data: JSONEncoder().encode(p), encoding: .utf8) ?? "") ?? ""
    }

    /// Parse a scanned payload; nil if malformed or missing required fields.
    static func parse(_ s: String) -> Pairing? {
        guard let data = s.data(using: .utf8),
              let p = try? JSONDecoder().decode(Pairing.self, from: data),
              !p.syncKey.isEmpty, !p.backendUrl.isEmpty, !p.anonKey.isEmpty else { return nil }
        return p
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
