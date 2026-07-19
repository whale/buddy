import Foundation
import CryptoKit

// MARK: - SupabaseCASStore (iOS) — the real network adapter behind the sync loop.
// Swift mirror of makeSupabaseCASStore()+makeEncryptedStore() in dist/index.html.
// Dumb transport only: it POSTs to the buddy_pull / buddy_push RPCs and converts
// SyncSnapshot ↔ the SyncWire JSON (epoch-ms) at the boundary, so iOS and Mac blobs
// are compatible. All merge / conflict logic stays in BuddySync.syncOnce.
//
// E2E: everything past this adapter speaks ciphertext — the wire blob is a BlobCrypto
// envelope; the engine and merge only ever see plaintext snapshots. Legacy plaintext
// rows decode fine and come back flagged `plain:true` so syncOnce re-pushes them
// encrypted (the one-time upgrade).
struct SupabaseCASStore: CASStore {
    let baseURL: URL
    let anonKey: String
    let device: String
    let blobKey: SymmetricKey
    // Reference-typed so the struct can remember a pre-hardening backend (no p_stats
    // param) after the first PGRST202 and stop doubling every push with a retry.
    private final class StatsSupport { var disabled = false }
    private let statsSupport = StatsSupport()

    init?(url: String, anonKey: String, syncKey: String, device: String = "ios") {
        let trimmed = url.hasSuffix("/") ? String(url.dropLast()) : url
        guard let u = URL(string: trimmed), !anonKey.isEmpty,
              let k = BlobCrypto.deriveKey(syncKey: syncKey) else { return nil }
        self.baseURL = u; self.anonKey = anonKey; self.device = device; self.blobKey = k
    }

    func pull(_ key: String) async throws -> PullResult {
        let rows = try await rpc("buddy_pull", ["p_key": key])
        guard let row = rows.first else { return PullResult(blob: nil, version: 0) }
        let d = try decode(row["blob"])
        return PullResult(blob: d.snap, version: intValue(row["version"]),
                          plain: d.plain, unreadable: d.unreadable, peerWire: d.peerWire)
    }

    func push(_ key: String, blob: SyncSnapshot, expected: Int) async throws -> PushResult {
        let wireData = try JSONEncoder().encode(SyncWire(blob))
        let envelope = try BlobCrypto.encryptEnvelope(wireData, key: blobKey)   // wire-2 cleartext-header envelope
        let base: [String: Any] = ["p_key": key, "p_blob": envelope,
                                   "p_expected": expected, "p_device": device]
        var rows: [[String: Any]]
        if statsSupport.disabled {
            rows = try await rpc("buddy_push", base)
        } else {
            do {
                rows = try await rpc("buddy_push", base.merging(["p_stats": stats(of: blob)]) { $1 })
            } catch {
                // Self-hosted backend on the pre-hardening schema: buddy_push has no p_stats
                // param, so PostgREST can't match the call (PGRST202/404). Retry without stats
                // rather than bricking their sync until they re-run hosted-setup.sql — and
                // remember, so their every push isn't doubled forever.
                let msg = error.localizedDescription
                if msg.contains("PGRST202") || msg.contains(" 404") {
                    statsSupport.disabled = true
                    rows = try await rpc("buddy_push", base)
                } else { throw error }
            }
        }
        guard let row = rows.first else { return PushResult(ok: false, blob: nil, version: 0) }
        let d = try decode(row["blob"])   // CAS-conflict blob may be an envelope too
        return PushResult(ok: (row["ok"] as? Bool) ?? false,
                          blob: d.snap,
                          version: intValue(row["version"]),
                          unreadable: d.unreadable, peerWire: d.peerWire)
    }

    // Metrics beside the ciphertext: COUNTS, NEVER CONTENT (server also enforces
    // numbers-only — same covenant as BuddyDiag). Mirror of the Mac's blobStats().
    private func stats(of b: SyncSnapshot) -> [String: Int] {
        let items = b.today?.items ?? []
        let done = items.filter { $0.state == .done }.count
        return ["active": items.count - done, "done": done,
                "deferred": b.deferred.count, "historyDays": b.history.count]
    }

    // MARK: - transport
    private func rpc(_ fn: String, _ body: [String: Any]) async throws -> [[String: Any]] {
        var req = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/\(fn)"))
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "BuddySync", code: -1, userInfo: [NSLocalizedDescriptionKey: "no HTTP response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let txt = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "BuddySync", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "rpc \(fn) \(http.statusCode): \(txt)"])
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    /// Wire value → (snapshot, wasPlaintext). Envelopes decrypt; legacy plaintext decodes
    /// directly and is flagged for the encrypt-on-next-push upgrade. HYBRIDS (a pre-E2E
    /// peer's plaintext with stale envelope keys echoed via extras) read as plaintext —
    /// the plaintext half is that peer's newer merge; decrypting the stale ct would
    /// silently discard it (mixed-version split-brain). SyncWire.knownKeys strips the
    /// envelope keys so they never ride extras back onto the wire.
    private struct Decoded { let snap: SyncSnapshot?; let plain: Bool; let unreadable: Bool; let peerWire: Int }
    private func decode(_ any: Any?) throws -> Decoded {
        guard let any = any, !(any is NSNull) else { return Decoded(snap: nil, plain: false, unreadable: false, peerWire: 0) }
        // wire-2 envelope: TRIAGE the cleartext header before decrypting.
        if BlobCrypto.isV2Envelope(any) {
            let minReader = BlobCrypto.envelopeMinReader(any) ?? 0
            if minReader > BlobCrypto.wireMax {           // newer than we can read → DEGRADE, never clobber
                BuddyDiag.log("sync-peer-newer", ["minReader": minReader])
                return Decoded(snap: nil, plain: false, unreadable: true,
                               peerWire: BlobCrypto.envelopeWire(any) ?? minReader)
            }
            let data = try BlobCrypto.decryptEnvelope(any as! [String: Any], key: blobKey)
            return Decoded(snap: try JSONDecoder().decode(SyncWire.self, from: data).toSnapshot(),
                           plain: false, unreadable: false, peerWire: 0)
        }
        // Legacy wire-1 pure envelope {enc:1}: decode, then flag plain so syncOnce re-pushes
        // once to UPGRADE it to a wire-2 envelope (mirrors the Mac).
        if BlobCrypto.isEnvelope(any) {
            let data = try BlobCrypto.decrypt(any as! [String: Any], key: blobKey)
            return Decoded(snap: try JSONDecoder().decode(SyncWire.self, from: data).toSnapshot(),
                           plain: true, unreadable: false, peerWire: 0)
        }
        if BlobCrypto.isHybrid(any) { BuddyDiag.log("sync-hybrid-blob") }
        let data = try JSONSerialization.data(withJSONObject: any)
        return Decoded(snap: try JSONDecoder().decode(SyncWire.self, from: data).toSnapshot(),
                       plain: true, unreadable: false, peerWire: 0)
    }
    private func intValue(_ any: Any?) -> Int {
        if let n = any as? Int { return n }
        if let n = any as? NSNumber { return n.intValue }
        return 0
    }
}
