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

    // 13. Merge cap — the UNION re-clamps to hardCap, and over-cap tasks are MOVED TO FUTURE,
    // never deleted (whale 2026-07-19).
    func testMergeClampsActiveToHardCap() {
        let a = snap(today: TodayState(date: "2026-06-19", items: [
            item("a1","one"), item("a2","two"), item("a3","three"),
            item("a4","four"), item("a5","five"), item("a6","six")]), savedAt: 2000)
        let b = snap(today: TodayState(date: "2026-06-19", items: [
            item("b7","seven"), item("b8","eight")]), savedAt: 1900)
        let m = BuddyMerge.merge(a, b)
        let active = (m?.today?.items ?? []).filter { $0.isActive }.count
        XCTAssertEqual(active, BuddyStore.hardCap)
        let parked = Set((m?.deferred ?? []).map { $0.id })
        XCTAssertTrue(parked.contains("b7") && parked.contains("b8"), "over-cap tasks parked in Future, not deleted")
        XCTAssertFalse((m?.today?.items ?? []).contains { $0.id == "b7" || $0.id == "b8" })
        XCTAssertEqual(m?.syncNotice?.moved, 2)
        XCTAssertEqual(m?.syncNotice?.combined, 8)
        XCTAssertEqual(m?.syncNotice?.dismissed, false)
    }

    // 13b. Mac WINS the slots: iPhone-minted (UPPERCASE id) tasks overflow first, even when the
    // iPhone save is newer. Six Mac tasks keep their slots; two iPhone tasks go to Future.
    func testMacTasksWinSlotsOveriPhone() {
        let macFull = snap(today: TodayState(date: "d", items: [
            item("c1","m1"), item("c2","m2"), item("c3","m3"),
            item("c4","m4"), item("c5","m5"), item("c6","m6")]), savedAt: 1000)
        let iosTwo = snap(today: TodayState(date: "d", items: [
            item("AA11","p1"), item("BB22","p2")]), savedAt: 9000)   // NEWER, still overflows
        let m = BuddyMerge.merge(macFull, iosTwo)
        let active = Set((m?.today?.items ?? []).filter { $0.isActive }.map { $0.id })
        let parked = Set((m?.deferred ?? []).map { $0.id })
        XCTAssertTrue(["c1","c2","c3","c4","c5","c6"].allSatisfy { active.contains($0) }, "Mac tasks keep slots")
        XCTAssertTrue(parked.contains("AA11") && parked.contains("BB22"), "iPhone tasks overflow to Future")
        XCTAssertFalse(active.contains("AA11") || active.contains("BB22"))
    }

    // 13c. Determinism: both directions relocate the identical set; re-merging the settled
    // result is a fixpoint (no re-overflow, no churn) → devices converge.
    func testOverflowIsSymmetricAndFixpoint() {
        let macFull = snap(today: TodayState(date: "d", items: [
            item("c1","m1"), item("c2","m2"), item("c3","m3"),
            item("c4","m4"), item("c5","m5"), item("c6","m6")]), savedAt: 1000)
        let iosTwo = snap(today: TodayState(date: "d", items: [item("AA11","p1"), item("BB22","p2")]), savedAt: 9000)
        let m1 = BuddyMerge.merge(macFull, iosTwo)!
        let m2 = BuddyMerge.merge(iosTwo, macFull)!
        XCTAssertEqual(Set(m1.deferred.map { $0.id }), Set(m2.deferred.map { $0.id }), "symmetric relocation")
        let settled = snap(today: m1.today, deferred: m1.deferred, savedAt: 9000)
        let m3 = BuddyMerge.merge(settled, settled)!
        XCTAssertEqual((m3.today?.items ?? []).filter { $0.isActive }.count, BuddyStore.hardCap)
        XCTAssertEqual(m3.deferred.count, m1.deferred.count, "no re-overflow on re-merge")
    }

    // 13e. Dismiss is sticky + syncs: a dismissed notice on one side stays dismissed after a
    // merge with a peer that hasn't dismissed (moved=0 path → pickNotice ORs dismissed).
    func testDismissedNoticeStaysDismissed() {
        var a = snap(savedAt: 2000); a.syncNotice = SyncNotice(combined: 8, moved: 2, dismissed: true)
        var b = snap(savedAt: 3000); b.syncNotice = SyncNotice(combined: 8, moved: 2, dismissed: false)
        XCTAssertEqual(BuddyMerge.merge(a, b)?.syncNotice?.dismissed, true)
        XCTAssertEqual(BuddyMerge.merge(b, a)?.syncNotice?.dismissed, true)
    }

    // 13f. TRUTHFUL counts when an overflow item is ALREADY parked on the peer: only the
    // NEWLY-relocated task counts (adversarial review finding, 2026-07-19). A: 6 Mac tasks + U1
    // parked; B: U1 + U2 still active. Union overflows by 2, but U1 is already parked → moved == 1.
    func testNoticeCountsOnlyNewlyMovedTasks() {
        let a = snap(today: TodayState(date: "d", items: [
            item("a1","1"), item("a2","2"), item("a3","3"),
            item("a4","4"), item("a5","5"), item("a6","6")]),
            deferred: [DeferredTask(id: "U1", text: "p1", wake: "", v: 1)], savedAt: 2000)
        let b = snap(today: TodayState(date: "d", items: [item("U1","p1"), item("U2","p2")]), savedAt: 1900)
        let m = BuddyMerge.merge(a, b)
        XCTAssertEqual(m?.syncNotice?.moved, 1, "already-parked overflow item must not inflate the count")
        XCTAssertEqual(m?.syncNotice?.combined, 7)
    }

    // 14. Merge dedupe — same title from both devices (different ids) collapses to one;
    // done items are never counted against the cap nor dropped by the clamp.
    func testMergeDedupesSameTitleAndKeepsDone() {
        let a = snap(today: TodayState(date: "2026-06-19", items: [
            item("m1","Check on Anthropic bill"), item("dn","archived",.done,1, Date(timeIntervalSince1970: 1))]), savedAt: 2000)
        let b = snap(today: TodayState(date: "2026-06-19", items: [
            item("i1","Check on Anthropic bill")]), savedAt: 1900)
        let m = BuddyMerge.merge(a, b)
        let bills = (m?.today?.items ?? []).filter { $0.isActive && $0.text == "Check on Anthropic bill" }.count
        XCTAssertEqual(bills, 1)
        XCTAssertTrue((m?.today?.items ?? []).contains { $0.id == "dn" && $0.isDone })
    }
}
