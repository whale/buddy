import Foundation
import CryptoKit

// MARK: - BlobCrypto — E2E encryption of the sync blob (Swift mirror of dist/index.html).
//
// The synced document is encrypted ON DEVICE before it reaches the wire; the server
// stores ciphertext it cannot read. The key derives from the syncKey — which the server
// NEVER sees (only sha256(syncKey) travels as owner_id) — so this rides the existing
// capability model: same QR, same pairing, nothing new to lose.
//
// Envelope on the wire: { enc:1, iv:<b64url 12B>, ct:<b64url ciphertext+GCM tag> }.
//
// Mac and iOS MUST agree byte-for-byte. Parameters (pinned by the shared test vector in
// BlobCryptoTests / syncTest 12a): HKDF-SHA256, EMPTY salt, info "buddy-blob-v1", 32-byte
// output → AES-256-GCM. WebCrypto emits ciphertext||tag; CryptoKit's sealedBox splits
// them — we concatenate to match.
enum BlobCrypto {
    static let info = "buddy-blob-v1"

    // MARK: base64url (the sync world's alphabet — same as generateSyncKey)
    static func b64uEncode(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    static func b64uDecode(_ s: String) -> Data? {
        var b64 = s.replacingOccurrences(of: "-", with: "+")
                   .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        return Data(base64Encoded: b64)
    }

    /// syncKey (43-char base64url, 256-bit) → AES-256-GCM key. nil on a malformed key.
    static func deriveKey(syncKey: String) -> SymmetricKey? {
        guard let ikm = b64uDecode(syncKey), ikm.count == 32 else { return nil }
        // No-salt overload == empty salt (matches WebCrypto's salt: new Uint8Array(0)).
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm),
                                      info: Data(info.utf8), outputByteCount: 32)
    }

    /// Encrypt wire-JSON bytes → envelope. `nonce` is for the cross-platform test vector only.
    static func encrypt(_ plaintext: Data, key: SymmetricKey, nonce: Data? = nil) throws -> [String: Any] {
        let n = try nonce.map { try AES.GCM.Nonce(data: $0) } ?? AES.GCM.Nonce()
        let box = try AES.GCM.seal(plaintext, using: key, nonce: n)
        return ["enc": 1,
                "iv": b64uEncode(Data(n)),
                "ct": b64uEncode(box.ciphertext + box.tag)]   // WebCrypto layout: ct||tag
    }

    /// Envelope → wire-JSON bytes. Throws on tamper/corruption (never adopt garbage).
    static func decrypt(_ envelope: [String: Any], key: SymmetricKey) throws -> Data {
        guard let ivS = envelope["iv"] as? String, let ctS = envelope["ct"] as? String,
              let iv = b64uDecode(ivS), let ctAndTag = b64uDecode(ctS), ctAndTag.count > 16
        else { throw NSError(domain: "BlobCrypto", code: 1,
                             userInfo: [NSLocalizedDescriptionKey: "malformed envelope"]) }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv),
                                        ciphertext: ctAndTag.dropLast(16),
                                        tag: ctAndTag.suffix(16))
        return try AES.GCM.open(box, using: key)
    }

    /// Is this wire value a PURE encryption envelope (vs plaintext or a hybrid)?
    /// A pre-E2E peer that pulled an encrypted row echoes {enc,iv,ct} back through
    /// its extras bag alongside its own PLAINTEXT state (hybrid blob) — the stale
    /// ct there predates that peer's merge, so a blob with plaintext markers must
    /// be read as plaintext (see isHybrid + SupabaseCASStore.decode).
    static func isEnvelope(_ any: Any?) -> Bool {
        guard let d = any as? [String: Any] else { return false }
        return (d["enc"] as? Int) == 1 && d["iv"] is String && d["ct"] is String
            && d["today"] == nil && d["savedAt"] == nil
    }

    /// Envelope keys riding beside plaintext (the mixed-version hybrid).
    static func isHybrid(_ any: Any?) -> Bool {
        guard let d = any as? [String: Any] else { return false }
        return (d["enc"] as? Int) == 1 && d["ct"] is String
            && (d["today"] != nil || d["savedAt"] != nil)
    }

    // MARK: - Wire v2 envelope — cleartext, AAD-authenticated triage header.
    // Swift mirror of dist/index.html encryptEnvelope/decryptEnvelope (SYNC-COMPAT.md).
    // {b,wire,crypto,minReader} are CLEARTEXT so any reader — and the server — can decide
    // "can I safely touch this" WITHOUT the key; the header is bound as AES-GCM AAD so a
    // tampered/downgraded header fails decryption. Content stays fully E2E-encrypted.
    // wire/crypto/schema are three INDEPENDENT axes. Pinned by the shared wire-2 vector in
    // BlobCryptoTests / syncTest 12c-vec — Mac and iOS MUST agree byte-for-byte.
    static let wireMax = 2       // highest framing this build can READ
    static let wireWrite = 2     // framing this build WRITES
    static let cryptoSuite = "aes256gcm.hkdf.v1"

    /// Fixed-order string ⇒ byte-identical AAD on JS and Swift (no canonical-JSON ambiguity).
    static func aad(wire: Int, suite: String, minReader: Int) -> Data {
        Data("buddy|\(wire)|\(suite)|\(minReader)".utf8)
    }
    static func intField(_ any: Any?) -> Int? {
        if let n = any as? Int { return n }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }

    /// Encrypt wire-JSON bytes → wire-2 envelope. `nonce` is for the cross-platform vector only.
    static func encryptEnvelope(_ plaintext: Data, key: SymmetricKey, nonce: Data? = nil, plat: String = "ios") throws -> [String: Any] {
        let wire = wireWrite, minReader = wireWrite, suite = cryptoSuite
        let n = try nonce.map { try AES.GCM.Nonce(data: $0) } ?? AES.GCM.Nonce()
        let box = try AES.GCM.seal(plaintext, using: key, nonce: n,
                                   authenticating: aad(wire: wire, suite: suite, minReader: minReader))
        return ["b": "buddy", "wire": wire, "crypto": suite, "minReader": minReader,
                "writer": ["app": "?", "plat": plat],
                "iv": b64uEncode(Data(n)),
                "ct": b64uEncode(box.ciphertext + box.tag)]   // WebCrypto layout: ct||tag
    }

    /// Wire-2 envelope → wire-JSON bytes. AAD is rebuilt from the envelope's OWN header,
    /// so a tampered header (downgrade attack) makes AES-GCM authentication fail.
    static func decryptEnvelope(_ env: [String: Any], key: SymmetricKey) throws -> Data {
        guard let ivS = env["iv"] as? String, let ctS = env["ct"] as? String,
              let iv = b64uDecode(ivS), let ctAndTag = b64uDecode(ctS), ctAndTag.count > 16,
              let wire = intField(env["wire"]), let suite = env["crypto"] as? String,
              let minReader = intField(env["minReader"])
        else { throw NSError(domain: "BlobCrypto", code: 3,
                             userInfo: [NSLocalizedDescriptionKey: "malformed v2 envelope"]) }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv),
                                        ciphertext: ctAndTag.dropLast(16), tag: ctAndTag.suffix(16))
        return try AES.GCM.open(box, using: key,
                                authenticating: aad(wire: wire, suite: suite, minReader: minReader))
    }

    /// A wire-2 envelope: cleartext header + ciphertext, no plaintext data markers.
    static func isV2Envelope(_ any: Any?) -> Bool {
        guard let d = any as? [String: Any] else { return false }
        return (d["b"] as? String) == "buddy" && intField(d["wire"]) != nil
            && d["iv"] is String && d["ct"] is String
            && d["today"] == nil && d["savedAt"] == nil
    }
    static func envelopeWire(_ any: Any?) -> Int? { (any as? [String: Any]).flatMap { intField($0["wire"]) } }
    static func envelopeMinReader(_ any: Any?) -> Int? { (any as? [String: Any]).flatMap { intField($0["minReader"]) } }
}
