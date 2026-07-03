import XCTest
@testable import Buddy

// P1.5 — the BuddyStore ↔ SyncSnapshot bridge (snapshot() / adopt()).
final class BuddyStoreSyncTests: XCTestCase {

    private func task(_ id: String, _ text: String, _ state: TaskState = .neutral, v: Int = 1) -> BuddyTask {
        BuddyTask(id: id, text: text, state: state, v: v)
    }

    // adopt(snapshot) then snapshot() reflects exactly what was adopted (round-trip identity).
    func testAdoptThenSnapshotRoundTrips() {
        let store = BuddyStore()
        let snap = SyncSnapshot(
            today: TodayState(date: "2026-06-21", items: [task("A", "a"), task("B", "b")], morningDone: true),
            history: [Day(date: "2026-06-20", weekday: "Friday",
                          items: [DayItem(id: "h-2026-06-20-0", text: "y", done: true)])],
            deferred: [DeferredTask(id: "d", text: "later", wake: "2026-06-25")],
            settings: .default, tombstones: ["gone": 1_750_000_000], erasedAt: nil, savedAt: 1000)

        store.adopt(snap)

        XCTAssertEqual(store.today.items.map { $0.id }, ["A", "B"])
        XCTAssertTrue(store.today.morningDone)
        XCTAssertEqual(store.history.first?.date, "2026-06-20")
        XCTAssertEqual(store.deferred.first?.id, "d")

        let out = store.snapshot()
        XCTAssertEqual(out.today?.items.map { $0.id }, ["A", "B"])
        XCTAssertEqual(out.history.first?.items.first?.text, "y")
        XCTAssertEqual(out.tombstones["gone"], 1_750_000_000)
    }

    // adopt(merge(local, remote)) applies the remote's edit + addition without losing local.
    func testAdoptMergedAppliesRemoteEdits() {
        let store = BuddyStore()
        store.adopt(SyncSnapshot(today: TodayState(date: "2026-06-21", items: [task("A", "orig", v: 1)]),
                                 history: [], deferred: [], settings: .default,
                                 tombstones: [:], erasedAt: nil, savedAt: 1000))

        // Remote edited A (v2) and added B.
        let remote = SyncSnapshot(
            today: TodayState(date: "2026-06-21", items: [task("A", "edited", v: 2), task("B", "new", v: 1)]),
            history: [], deferred: [], settings: .default, tombstones: [:], erasedAt: nil, savedAt: 2000)

        let merged = BuddyMerge.merge(store.snapshot(), remote)
        XCTAssertNotNil(merged)
        store.adopt(merged!)

        XCTAssertEqual(store.today.items.count, 2)
        XCTAssertEqual(store.today.items.first(where: { $0.id == "A" })?.text, "edited")   // higher v wins
        XCTAssertTrue(store.today.items.contains { $0.id == "B" })                          // remote add kept
    }

    // adopt() must NOT fire the onLocalChange push signal (that would ping-pong).
    func testAdoptDoesNotFireLocalChange() {
        let store = BuddyStore()
        var fired = false
        store.onLocalChange = { fired = true }
        store.adopt(SyncSnapshot(today: TodayState(date: "2026-06-21", items: [task("A", "a")]),
                                 history: [], deferred: [], settings: .default,
                                 tombstones: [:], erasedAt: nil, savedAt: 1000))
        XCTAssertFalse(fired, "adopting a remote snapshot must not schedule a push")
    }

    // A genuine local mutation DOES fire onLocalChange (the dirty trigger the engine needs).
    func testLocalMutationFiresLocalChange() {
        let store = BuddyStore()
        store.adopt(SyncSnapshot(today: TodayState(date: BuddyStore.localDate(), items: []),
                                 history: [], deferred: [], settings: .default,
                                 tombstones: [:], erasedAt: nil, savedAt: 1000))
        var fired = false
        store.onLocalChange = { fired = true }
        _ = store.addTask()
        XCTAssertTrue(fired, "a local edit must signal the sync engine")
    }
}
