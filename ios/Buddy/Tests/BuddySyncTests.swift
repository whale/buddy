import XCTest
@testable import Buddy

// Sync step 5 (iOS) — the CAS-on-client loop + wire codec. Mirrors the Mac's
// __buddy.syncTest() scenario-for-scenario, against the in-memory CAS store.
final class BuddySyncTests: XCTestCase {

    // MARK: - builders
    private func snap(_ items: [BuddyTask] = [], history: [Day] = [], deferred: [DeferredTask] = [],
                      tombstones: [String: Double] = [:], erasedAt: Double? = nil,
                      settings: BuddySettings? = .default, savedAt: Double = 1000) -> SyncSnapshot {
        SyncSnapshot(today: TodayState(date: "2026-06-19", items: items), history: history,
                     deferred: deferred, settings: settings, tombstones: tombstones,
                     erasedAt: erasedAt, savedAt: savedAt)
    }
    private func item(_ id: String, _ text: String, _ v: Int = 1, _ st: TaskState = .neutral) -> BuddyTask {
        BuddyTask(id: id, text: text, state: st, v: v)
    }
    private func ids(_ s: SyncSnapshot?) -> [String] { (s?.today?.items ?? []).map { $0.id }.sorted() }

    // 1. First push seeds an empty store at version 1.
    func testFirstPushSeeds() async throws {
        let store = InMemoryCASStore()
        let r = try await BuddySync.syncOnce(store: store, key: "k", local: snap([item("a","alpha"), item("b","beta")]))
        XCTAssertTrue(r.ok && r.pushed)
        let v = await store.currentVersion("k")
        XCTAssertEqual(v, 1)
        let blob = await store.currentBlob("k")
        XCTAssertEqual(ids(blob), ["a","b"])
    }

    // 2. Empty local + full server → pull-only, no version churn.
    func testEmptyOverFullGuard() async throws {
        let store = InMemoryCASStore(seed: ("k", snap([item("a","alpha"), item("b","beta")], savedAt: 5000), 3))
        let r = try await BuddySync.syncOnce(store: store, key: "k", local: snap([]))
        XCTAssertTrue(r.ok && r.pulled && !r.pushed)
        let v = await store.currentVersion("k")
        XCTAssertEqual(v, 3)                                         // not bumped
        XCTAssertEqual(ids(r.merged), ["a","b"])                     // device adopts server
    }

    // 3. Two devices, different-task edits, both survive (the core LWW failure).
    func testTwoDeviceMerge() async throws {
        let store = InMemoryCASStore()
        _ = try await BuddySync.syncOnce(store: store, key: "k", local: snap([item("t1","base",1)]))      // seed t1 v1
        _ = try await BuddySync.syncOnce(store: store, key: "k", local: snap([item("t1","A-edit",2)]))    // device A
        _ = try await BuddySync.syncOnce(store: store, key: "k", local: snap([item("t1","base",1), item("t2","B-new",1)])) // device B
        let blob = await store.currentBlob("k")
        XCTAssertEqual(ids(blob), ["t1","t2"])
        XCTAssertEqual(blob?.today?.items.first { $0.id == "t1" }?.text, "A-edit")
        XCTAssertEqual(blob?.today?.items.first { $0.id == "t2" }?.text, "B-new")
    }

    // 4. CAS conflict + retry: a concurrent write between pull and push is folded in.
    func testConflictRetry() async throws {
        let injected = snap([item("p","mine"), item("q","other-device")], savedAt: 2000)
        let store = ConflictOnceStore(blob: snap([item("p","mine")], savedAt: 1000), version: 1, injected: injected)
        let r = try await BuddySync.syncOnce(store: store, key: "k",
                    local: snap([item("p","mine"), item("r","late-add")], savedAt: 3000))
        XCTAssertTrue(r.ok && r.pushed)
        let (blob, _) = await store.cur()
        XCTAssertEqual(ids(blob), ["p","q","r"])                    // nothing lost
    }

    // 5. Idempotent re-sync is a no-op (no version churn).
    func testIdempotentNoop() async throws {
        let store = InMemoryCASStore()
        _ = try await BuddySync.syncOnce(store: store, key: "k", local: snap([item("z","z")]))
        let v1 = await store.currentVersion("k")
        let r = try await BuddySync.syncOnce(store: store, key: "k", local: snap([item("z","z")]))
        XCTAssertTrue(r.noop)
        let v2 = await store.currentVersion("k")
        XCTAssertEqual(v2, v1)
    }

    // 6. Tombstone propagates — device B must not resurrect a deleted task.
    func testTombstonePropagates() async throws {
        let store = InMemoryCASStore()
        _ = try await BuddySync.syncOnce(store: store, key: "k", local: snap([item("x","x"), item("y","y")]))
        _ = try await BuddySync.syncOnce(store: store, key: "k", local: snap([item("y","y")], tombstones: ["x": 9999])) // A deletes x
        _ = try await BuddySync.syncOnce(store: store, key: "k", local: snap([item("x","x"), item("y","y")]))           // B still has x
        let blob = await store.currentBlob("k")
        XCTAssertEqual(ids(blob), ["y"])
        XCTAssertNotNil(blob?.tombstones["x"])
    }

    // 7. Erase-all propagates over a full remote (guard must NOT block a real wipe).
    func testErasePropagates() async throws {
        let store = InMemoryCASStore(seed: ("k", snap([item("old","old")], savedAt: 1), 2))
        let r = try await BuddySync.syncOnce(store: store, key: "k", local: snap([], erasedAt: 9_999_999))
        XCTAssertTrue(r.pushed)
        let blob = await store.currentBlob("k")
        XCTAssertEqual(blob?.today?.items.count, 0)
        XCTAssertNotNil(blob?.erasedAt)
    }

    // 7b. MUTUAL UNLINK: a bucket stamped with `unlinkedAt` makes the peer's pass report
    // `.unlinked` (read BEFORE merge) and must NOT push/clobber the marker away.
    func testMutualUnlinkDetected() async throws {
        var stamped = snap([item("keep","keep")])
        stamped.unlinkedAt = 1_750_000_000
        let store = InMemoryCASStore(seed: ("k", stamped, 5))
        let r = try await BuddySync.syncOnce(store: store, key: "k", local: snap([item("mine","mine")]))
        XCTAssertTrue(r.unlinked, "peer pass reports unlinked")
        let ver = await store.currentVersion("k")
        let stampedBlob = await store.currentBlob("k")
        XCTAssertEqual(ver, 5, "marker must not be clobbered")
        XCTAssertEqual(stampedBlob?.unlinkedAt, 1_750_000_000)
        // A normal (un-stamped) bucket → no false unlink.
        let store2 = InMemoryCASStore(seed: ("k", snap([item("x","x")]), 2))
        let r2 = try await BuddySync.syncOnce(store: store2, key: "k", local: snap([item("x","x")]))
        XCTAssertFalse(r2.unlinked)
    }

    // 7b2. CONCURRENT unlink race (adversarial finding 2026-07-19): a pass is mid-CAS when the peer
    // stamps the bucket. The conflict must be read as `.unlinked` — NOT folded+repushed, which would
    // ERASE the marker (merge() drops unlinkedAt) and tell the user it worked.
    func testConcurrentUnlinkMarkerNotErased() async throws {
        var stamped = snap([item("p","mine")], savedAt: 2000)
        stamped.unlinkedAt = 1_750_000_000
        let store = ConflictOnceStore(blob: snap([item("p","mine")], savedAt: 1000), version: 1, injected: stamped)
        let r = try await BuddySync.syncOnce(store: store, key: "k",
                    local: snap([item("p","mine"), item("r","late")], savedAt: 3000))
        XCTAssertTrue(r.unlinked, "mid-CAS marker must be read as unlinked, not merged away")
        let (blob, _) = await store.cur()
        XCTAssertEqual(blob.unlinkedAt, 1_750_000_000, "marker preserved on the server, not clobbered")
    }

    // 7c. The unlink marker survives the wire round-trip (seconds ↔ ms), like erasedAt.
    func testUnlinkMarkerWireRoundTrip() throws {
        var s = snap([item("a","a")]); s.unlinkedAt = 1_750_000_000
        let wire = SyncWire(s)
        XCTAssertEqual(try XCTUnwrap(wire.unlinkedAt), 1_750_000_000 * 1000, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(wire.toSnapshot().unlinkedAt), 1_750_000_000, accuracy: 0.001)
    }

    // 8. SyncWire round-trip preserves data AND converts seconds ↔ wire milliseconds.
    func testWireRoundTripAndUnits() throws {
        let s = snap([item("a","alpha",2)], history: [Day(date: "2026-06-18", weekday: "Thu",
                        items: [DayItem(id: "h-2026-06-18-0", text: "h", done: true)])],
                     tombstones: ["d": 1_700_000_000], erasedAt: 1_700_000_500, savedAt: 1_700_000_123)
        let wire = SyncWire(s)
        XCTAssertEqual(wire.savedAt, 1_700_000_123 * 1000, accuracy: 0.001)      // seconds → ms on the wire
        XCTAssertEqual(try XCTUnwrap(wire.tombstones["d"]), 1_700_000_000 * 1000, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(wire.erasedAt), 1_700_000_500 * 1000, accuracy: 0.001)

        // JSON round-trip then back to a snapshot (ms → seconds).
        let data = try JSONEncoder().encode(wire)
        let back = try JSONDecoder().decode(SyncWire.self, from: data).toSnapshot()
        XCTAssertEqual(back.savedAt, 1_700_000_123, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(back.tombstones["d"]), 1_700_000_000, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(back.erasedAt), 1_700_000_500, accuracy: 0.001)
        XCTAssertEqual(ids(back), ["a"])
        XCTAssertEqual(back.today?.items.first?.v, 2)
        XCTAssertEqual(back.history.first?.items.first?.id, "h-2026-06-18-0")
    }

    // 9. morningDone survives merge + wire (regression: was hardcoded false → re-triggered
    //    the Mac's morning screen after syncing with a phone).
    func testMorningDoneParity() throws {
        // OR-wins merge
        let a = SyncSnapshot(today: TodayState(date: "d", items: [], morningDone: true), history: [], deferred: [], settings: .default, tombstones: [:], erasedAt: nil, savedAt: 2000)
        let b = SyncSnapshot(today: TodayState(date: "d", items: [], morningDone: false), history: [], deferred: [], settings: .default, tombstones: [:], erasedAt: nil, savedAt: 1000)
        XCTAssertEqual(BuddyMerge.merge(a, b)?.today?.morningDone, true)
        // wire round-trip preserves it
        let back = try JSONDecoder().decode(SyncWire.self, from: JSONEncoder().encode(SyncWire(a))).toSnapshot()
        XCTAssertEqual(back.today?.morningDone, true)
    }
}

// A store that lets one concurrent writer land between the client's pull and its
// first push — exercises the CAS retry path deterministically.
actor ConflictOnceStore: CASStore {
    private var blob: SyncSnapshot
    private var version: Int
    private var fired = false
    private let injected: SyncSnapshot
    init(blob: SyncSnapshot, version: Int, injected: SyncSnapshot) {
        self.blob = blob; self.version = version; self.injected = injected
    }
    func pull(_ key: String) -> PullResult { PullResult(blob: blob, version: version) }
    func push(_ key: String, blob newBlob: SyncSnapshot, expected: Int) -> PushResult {
        if !fired {                                   // simulate another device writing first
            fired = true
            blob = injected; version += 1
            return PushResult(ok: false, blob: blob, version: version)
        }
        if expected == version {
            blob = newBlob; version += 1
            return PushResult(ok: true, blob: newBlob, version: version)
        }
        return PushResult(ok: false, blob: blob, version: version)
    }
    func cur() -> (SyncSnapshot, Int) { (blob, version) }
}
