import XCTest
@testable import Buddy

// Sync step 3 — the pure merge() suite. Mirrors the Mac web app's mergeTest()
// (dist/index.html) scenario-for-scenario. These are the data-loss cases the
// adversarial review demanded: nothing a user did on either device may vanish.
final class BuddyMergeTests: XCTestCase {

    // MARK: - builders
    private func snap(today: TodayState? = TodayState(date: "2026-06-19", items: []),
                      history: [Day] = [], deferred: [DeferredTask] = [],
                      settings: BuddySettings? = nil, tombstones: [String: Double] = [:],
                      erasedAt: Double? = nil, savedAt: Double = 1000) -> SyncSnapshot {
        SyncSnapshot(today: today, history: history, deferred: deferred,
                     settings: settings, tombstones: tombstones, erasedAt: erasedAt, savedAt: savedAt)
    }
    private func item(_ id: String, _ text: String, _ st: TaskState = .neutral,
                      _ v: Int = 1, _ doneAt: Date? = nil) -> BuddyTask {
        BuddyTask(id: id, text: text, state: st, doneAt: doneAt, v: v)
    }
    private func ids(_ m: SyncSnapshot?) -> [String] { (m?.today?.items ?? []).map { $0.id }.sorted() }

    // 1. Different-task edits on two devices BOTH survive (the core LWW failure).
    func testDifferentTaskEditsBothSurvive() {
        let a = snap(today: TodayState(date: "2026-06-19", items: [item("t1","A-edit",.neutral,2), item("t2","keep")]), savedAt: 2000)
        let b = snap(today: TodayState(date: "2026-06-19", items: [item("t1","old"), item("t2","B-edit",.neutral,2)]), savedAt: 1900)
        let m = BuddyMerge.merge(a, b)
        XCTAssertEqual(m?.today?.items.first { $0.id == "t1" }?.text, "A-edit")
        XCTAssertEqual(m?.today?.items.first { $0.id == "t2" }?.text, "B-edit")
    }

    // 2. Higher per-item v wins regardless of savedAt.
    func testHigherItemVersionWins() {
        let m = BuddyMerge.merge(
            snap(today: TodayState(date: "d", items: [item("x","new",.neutral,3)]), savedAt: 1000),
            snap(today: TodayState(date: "d", items: [item("x","stale",.neutral,2)]), savedAt: 5000))
        XCTAssertEqual(m?.today?.items.first { $0.id == "x" }?.text, "new")
        XCTAssertEqual(m?.today?.items.first { $0.id == "x" }?.v, 3)
    }

    // 3. Tombstone wins — a deleted id is never resurrected.
    func testTombstoneWins() {
        let m = BuddyMerge.merge(
            snap(today: TodayState(date: "d", items: []), tombstones: ["g": 1500], savedAt: 2000),
            snap(today: TodayState(date: "d", items: [item("g","ghost")]), savedAt: 1000))
        XCTAssertFalse(m?.today?.items.contains { $0.id == "g" } ?? true)
        XCTAssertEqual(m?.tombstones["g"], 1500)
    }

    // 4. erasedAt barrier voids a snapshot saved before the erase.
    func testErasedAtBarrierVoidsPreErase() {
        let m = BuddyMerge.merge(
            snap(today: TodayState(date: "d", items: []), history: [], erasedAt: 8000, savedAt: 9000),
            snap(today: TodayState(date: "d", items: [item("z","pre-erase",.neutral,9)]),
                 history: [Day(date: "2026-06-01", weekday: "Mon", items: [DayItem(id: "h-2026-06-01-0", text: "old", done: true)])], savedAt: 5000))
        XCTAssertEqual(m?.today?.items.count, 0)
        XCTAssertEqual(m?.history.count, 0)
        XCTAssertEqual(m?.erasedAt, 8000)
    }

    // 5. History union by date with done-wins (a completion never un-completes).
    func testHistoryUnionDoneWins() {
        let m = BuddyMerge.merge(
            snap(history: [Day(date: "2026-06-18", weekday: "Thu", items: [DayItem(id: "h-2026-06-18-0", text: "task", done: true)])], savedAt: 2000),
            snap(history: [Day(date: "2026-06-18", weekday: "Thu", items: [DayItem(id: "h-2026-06-18-0", text: "task", done: false)]),
                           Day(date: "2026-06-17", weekday: "Wed", items: [DayItem(id: "h-2026-06-17-0", text: "other", done: true)])], savedAt: 1000))
        XCTAssertEqual(m?.history.count, 2)
        // merged by id, done-wins, no duplicate item for the same id
        XCTAssertEqual(m?.history.first { $0.date == "2026-06-18" }?.items.count, 1)
        XCTAssertEqual(m?.history.first { $0.date == "2026-06-18" }?.items.first?.done, true)
    }

    // 6. Items present on only one side are kept (never dropped).
    func testOneSidedItemsKept() {
        let m = BuddyMerge.merge(
            snap(today: TodayState(date: "d", items: [item("a","aa")]), savedAt: 2000),
            snap(today: TodayState(date: "d", items: [item("b","bb")]), savedAt: 1000))
        XCTAssertEqual(ids(m), ["a","b"])
    }

    // 7. Commutative on the id set (order may differ, contents must not).
    func testCommutativeOnIdSet() {
        let a = snap(today: TodayState(date: "d", items: [item("t1","A",.neutral,2), item("t2","keep")]), savedAt: 2000)
        let b = snap(today: TodayState(date: "d", items: [item("t1","old"), item("t2","B",.neutral,2)]), savedAt: 1900)
        XCTAssertEqual(ids(BuddyMerge.merge(a, b)), ids(BuddyMerge.merge(b, a)))
    }

    // 8. Idempotent — merge(a,a) preserves items + versions exactly.
    func testIdempotent() {
        let a = snap(today: TodayState(date: "d", items: [item("t1","A",.neutral,2), item("t2","keep")]), savedAt: 2000)
        let m = BuddyMerge.merge(a, a)
        XCTAssertEqual(ids(m), ids(a))
        for it in m?.today?.items ?? [] {
            XCTAssertEqual(a.today?.items.first { $0.id == it.id }?.v, it.v)
        }
    }

    // 9. Null inputs — merge tolerates a missing side (fresh boot / broken store).
    func testNilInputs() {
        let a = snap(today: TodayState(date: "d", items: [item("a","aa")]), savedAt: 2000)
        XCTAssertEqual(ids(BuddyMerge.merge(nil, a)), ids(a))
        XCTAssertEqual(ids(BuddyMerge.merge(a, nil)), ids(a))
        XCTAssertNil(BuddyMerge.merge(nil, nil))
    }

    // 10. Tie on v → the more-recent completion wins.
    func testTieOnVersionNewerDoneWins() {
        let m = BuddyMerge.merge(
            snap(today: TodayState(date: "d", items: [item("c","old-done",.done,2, Date(timeIntervalSince1970: 100))]), savedAt: 1000),
            snap(today: TodayState(date: "d", items: [item("c","new-done",.done,2, Date(timeIntervalSince1970: 200))]), savedAt: 1001))
        XCTAssertEqual(m?.today?.items.first?.text, "new-done")
    }
}
