import XCTest
@testable import Buddy

// LIVE tests against a local Supabase (http://127.0.0.1:54321). They SKIP gracefully
// when the backend isn't running, so the normal suite stays green without it.
// Start it with: supabase start && supabase db reset
final class SupabaseSyncLiveTests: XCTestCase {
    let url = "http://127.0.0.1:54321"
    // Local CLI default publishable key. If it differs, the reachability probe 401s → skip.
    let key = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"

    private func backendOrSkip() async throws -> SupabaseCASStore {
        guard let store = SupabaseCASStore(url: url, anonKey: key, device: "ios-test") else {
            throw XCTSkip("could not construct store")
        }
        do { _ = try await store.pull("reachability-probe") }
        catch { throw XCTSkip("local Supabase not reachable — start it to run live tests (\(error.localizedDescription))") }
        return store
    }

    private func snap(_ items: [BuddyTask], savedAt: Double = 1_750_000_000) -> SyncSnapshot {
        SyncSnapshot(today: TodayState(date: "2026-06-21", items: items), history: [], deferred: [],
                     settings: .default, tombstones: [:], erasedAt: nil, savedAt: savedAt)
    }

    // CAS contract over the real network (push/pull/stale-reject/increment).
    func testLiveCASContract() async throws {
        let store = try await backendOrSkip()
        let k = "ios-live-" + UUID().uuidString
        let s = snap([BuddyTask(id: "x", text: "from iOS", state: .neutral, v: 1)])

        let p1 = try await store.push(k, blob: s, expected: 0)
        XCTAssertTrue(p1.ok); XCTAssertEqual(p1.version, 1)

        let pulled = try await store.pull(k)
        XCTAssertEqual(pulled.version, 1)
        XCTAssertEqual(pulled.blob?.today?.items.first?.text, "from iOS")

        let stale = try await store.push(k, blob: s, expected: 0)   // wrong expected → rejected
        XCTAssertFalse(stale.ok); XCTAssertEqual(stale.version, 1)

        let match = try await store.push(k, blob: s, expected: 1)   // correct expected → v2
        XCTAssertTrue(match.ok); XCTAssertEqual(match.version, 2)
    }

    // The real payoff: two devices, different tasks, both survive through the live DB.
    func testLiveTwoDeviceMerge() async throws {
        let store = try await backendOrSkip()
        let k = "ios-merge-" + UUID().uuidString

        let rA = try await BuddySync.syncOnce(store: store, key: k,
                    local: snap([BuddyTask(id: "A", text: "from device A", state: .neutral, v: 1)], savedAt: 1000))
        XCTAssertTrue(rA.ok)

        let rB = try await BuddySync.syncOnce(store: store, key: k,
                    local: snap([BuddyTask(id: "B", text: "from device B", state: .neutral, v: 1)], savedAt: 2000))
        XCTAssertTrue(rB.ok)
        XCTAssertEqual((rB.merged?.today?.items ?? []).map { $0.id }.sorted(), ["A", "B"])

        // And the backend itself holds both.
        let final = try await store.pull(k)
        XCTAssertEqual((final.blob?.today?.items ?? []).map { $0.id }.sorted(), ["A", "B"])
    }

    // Cross-platform: read a blob shaped exactly like the Mac writes (epoch-ms wire),
    // proving iOS decodes Mac-authored data correctly.
    func testLiveReadsMacShapedBlob() async throws {
        let store = try await backendOrSkip()
        let k = "ios-macshape-" + UUID().uuidString
        // Mac writes ms timestamps; push a snapshot and confirm round-trip through the DB.
        let s = snap([BuddyTask(id: "m", text: "made on Mac", state: .focused, v: 3)], savedAt: 1_750_000_999)
        _ = try await store.push(k, blob: s, expected: 0)
        let back = try await store.pull(k)
        XCTAssertEqual(back.blob?.today?.items.first?.text, "made on Mac")
        XCTAssertEqual(back.blob?.today?.items.first?.state, .focused)
        XCTAssertEqual(back.blob?.savedAt ?? 0, 1_750_000_999, accuracy: 1)   // ms→s survived the wire
    }

    // THE cross-app gate (catches B1 + M2 + wire drift at once): inject a GENUINE Mac-shaped
    // raw JSON blob (settings WITHOUT historyDays, `pinned` present, ms timestamps) directly via
    // buddy_push at the DERIVED ownerId, then pull it through the typed iOS store + run a full
    // syncOnce. If any of those regress, Mac→iOS silently dies — this fails loudly instead.
    func testLiveMacRawBlobDecodesAndMergesAtOwnerId() async throws {
        _ = try await backendOrSkip()
        let syncKey = "live-" + UUID().uuidString            // fresh key → fresh bucket per run
        let ownerId = SyncIdentity.ownerId(for: syncKey)     // M2: the row key BOTH devices derive

        // Exactly what dist/index.html serialize() emits — note: NO historyDays; pinned present.
        let macBlob: [String: Any] = [
            "version": 1,
            "savedAt": 1_750_000_000_000,
            "today": ["date": "2026-06-21", "morningDone": true, "items": [
                ["id": "mac1", "text": "made on Mac", "state": "neutral", "src": NSNull(), "doneAt": NSNull(), "v": 1]
            ]],
            "history": [], "deferred": [],
            "settings": ["celebrate": 80, "reserveSpace": false],
            "pinned": true,
            "tombstones": [:], "erasedAt": NSNull(), "restartStash": NSNull()
        ]
        try await rawPush(key: ownerId, blob: macBlob)

        // 1) The typed iOS store pulls + decodes the Mac blob (B1 guard, over the live DB).
        let store = SupabaseCASStore(url: url, anonKey: key, device: "ios-test")!
        let pulled = try await store.pull(ownerId)
        XCTAssertEqual(pulled.blob?.today?.items.first?.text, "made on Mac")
        XCTAssertEqual(pulled.blob?.settings?.historyDays, BuddySettings.default.historyDays) // defaulted
        XCTAssertEqual(pulled.blob?.savedAt ?? 0, 1_750_000_000, accuracy: 1)

        // 2) A full sync from an iOS device at the SAME ownerId merges both sides' tasks.
        let res = try await BuddySync.syncOnce(store: store, key: ownerId,
                    local: snap([BuddyTask(id: "ios1", text: "made on iPhone", state: .neutral, v: 1)], savedAt: 1_750_000_500))
        XCTAssertTrue(res.ok)
        let final = try await store.pull(ownerId)
        XCTAssertEqual((final.blob?.today?.items ?? []).map { $0.id }.sorted(), ["ios1", "mac1"])
    }

    // TRUE cross-platform E2E: pull a blob the REAL Mac app (dist/index.html) pushed via its
    // own serialize()+setSync at a fixed pairing key, and decode it with the iOS store. Skips
    // if the Mac hasn't pushed to this bucket yet (so it's not flaky), asserts when present.
    // Proves the actual Mac app → live DB → iOS decode path, not a hand-built lookalike.
    func testE2EMacAppBlobDecodesOnIOS() async throws {
        let store = try await backendOrSkip()
        let fixedKey = "0123456789012345678901234567890123456789012"   // same fixed key the Mac app pushed with
        let ownerId = SyncIdentity.ownerId(for: fixedKey)
        let pulled = try await store.pull(ownerId)
        guard let blob = pulled.blob, let item = blob.today?.items.first(where: { $0.id == "macToIOS" }) else {
            throw XCTSkip("Mac app hasn't pushed to this bucket — run the dist setSync push first")
        }
        XCTAssertEqual(item.text, "made on the Mac app")
        XCTAssertEqual(item.state, .done)                                              // shared state survives
        XCTAssertNotNil(item.doneAt)                                                   // ms→s doneAt decoded
        XCTAssertEqual(blob.today?.items.first(where: { $0.id == "macActive" })?.state, .neutral)
        XCTAssertEqual(blob.settings?.historyDays, BuddySettings.default.historyDays)  // B1: defaulted, not thrown
    }

    // Raw RPC: POST a hand-built jsonb to buddy_push (bypasses the typed encoder so the test
    // controls the EXACT on-wire shape — the whole point of the cross-app gate).
    private func rawPush(key: String, blob: [String: Any]) async throws {
        var req = URLRequest(url: URL(string: url + "/rest/v1/rpc/buddy_push")!)
        req.httpMethod = "POST"
        // Auth = the anon key (self.key); `key` is the row/owner id and goes in the body only.
        req.setValue(self.key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(self.key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "p_key": key, "p_blob": blob, "p_expected": 0, "p_device": "mac-test"])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw NSError(domain: "rawPush", code: code, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? ""])
        }
    }
}
