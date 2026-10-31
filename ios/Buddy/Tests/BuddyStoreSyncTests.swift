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

    // Field report 2026-10-31: "I added a 6th task, it took it for a second and then it
    // disappeared — twice." A poll pass snapshots while the new row is still blank, waits on the
    // network, and the user taps Return meanwhile. The pass's merge (blank row stripped) must NOT
    // be adopted over the committed task; the next pass, built from fresh state, keeps it.
    func testAdoptRefusesMergeBuiltFromStaleSnapshot() {
        let store = BuddyStore()
        let five = (1...5).map { task("T\($0)", "task \($0)") }
        let remote = SyncSnapshot(today: TodayState(date: BuddyStore.localDate(), items: five),
                                  history: [], deferred: [], settings: .default,
                                  tombstones: [:], erasedAt: nil, savedAt: 1000)
        store.adopt(remote)
        guard let id = store.addTask() else { return XCTFail("could not add a 6th task") }
        store.isEditing = true                    // TodayView.addTask sets this; typed text stays in the view

        // The pass: revision read, snapshot taken (new row still blank), merged against remote.
        let revision = store.localRevision
        guard let stale = BuddyMerge.merge(store.snapshot(), remote) else { return XCTFail("merge failed") }
        let staleIds = (stale.today?.items ?? []).map { $0.id }
        XCTAssertFalse(staleIds.contains(id), "precondition: merge strips the blank row")
        // A pass that returns while still typing is deferred — that part always worked.
        XCTAssertFalse(store.adopt(stale, basedOn: revision), "adopt must defer while a row is being edited")
        XCTAssertTrue(store.today.items.contains(where: { $0.id == id }))

        // Return lands while a pass is on the network (TodayView.commitEdit order: guard off, then commit)…
        store.isEditing = false
        store.commitEdit(id: id, text: "Practicing Japanese")

        // …and the pass comes back with its stale merge.
        XCTAssertFalse(store.adopt(stale, basedOn: revision), "a merge built before the commit was adopted")
        XCTAssertEqual(store.today.items.first(where: { $0.id == id })?.text, "Practicing Japanese",
                       "the committed 6th task was wiped by a stale sync adopt")

        // The re-run pass merges FRESH state and keeps the task.
        let fresh = store.localRevision
        guard let next = BuddyMerge.merge(store.snapshot(), stale) else { return XCTFail("merge failed") }
        XCTAssertTrue(store.adopt(next, basedOn: fresh))
        XCTAssertTrue(store.activeTasks.contains(where: { $0.id == id && $0.text == "Practicing Japanese" }))
        XCTAssertEqual(store.activeCount, 6)
    }

    // adopt() itself must not count as a local change, or every adopt would look stale.
    func testAdoptDoesNotBumpLocalRevision() {
        let store = BuddyStore()
        let before = store.localRevision
        store.adopt(SyncSnapshot(today: TodayState(date: BuddyStore.localDate(), items: [task("A", "a")]),
                                 history: [], deferred: [], settings: .default,
                                 tombstones: [:], erasedAt: nil, savedAt: 1000))
        XCTAssertEqual(store.localRevision, before)
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
