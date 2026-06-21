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
}
