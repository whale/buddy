import Foundation

// MARK: - SupabaseCASStore (iOS) — the real network adapter behind the sync loop.
// Swift mirror of makeSupabaseCASStore() in dist/index.html. Dumb transport only:
// it POSTs to the buddy_pull / buddy_push RPCs and converts SyncSnapshot ↔ the
// SyncWire JSON (epoch-ms) at the boundary, so iOS and Mac blobs are compatible.
// All merge / conflict logic stays in BuddySync.syncOnce.
struct SupabaseCASStore: CASStore {
    let baseURL: URL
    let anonKey: String
    let device: String

    init?(url: String, anonKey: String, device: String = "ios") {
        let trimmed = url.hasSuffix("/") ? String(url.dropLast()) : url
        guard let u = URL(string: trimmed), !anonKey.isEmpty else { return nil }
        self.baseURL = u; self.anonKey = anonKey; self.device = device
    }

    func pull(_ key: String) async throws -> PullResult {
        let rows = try await rpc("buddy_pull", ["p_key": key])
        guard let row = rows.first else { return PullResult(blob: nil, version: 0) }
        return PullResult(blob: try snapshot(from: row["blob"]), version: intValue(row["version"]))
    }

    func push(_ key: String, blob: SyncSnapshot, expected: Int) async throws -> PushResult {
        let wireObj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SyncWire(blob)))
        let rows = try await rpc("buddy_push",
            ["p_key": key, "p_blob": wireObj, "p_expected": expected, "p_device": device])
        guard let row = rows.first else { return PushResult(ok: false, blob: nil, version: 0) }
        return PushResult(ok: (row["ok"] as? Bool) ?? false,
                          blob: try snapshot(from: row["blob"]),
                          version: intValue(row["version"]))
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

    private func snapshot(from any: Any?) throws -> SyncSnapshot? {
        guard let any = any, !(any is NSNull) else { return nil }
        let data = try JSONSerialization.data(withJSONObject: any)
        return try JSONDecoder().decode(SyncWire.self, from: data).toSnapshot()
    }
    private func intValue(_ any: Any?) -> Int {
        if let n = any as? Int { return n }
        if let n = any as? NSNumber { return n.intValue }
        return 0
    }
}
