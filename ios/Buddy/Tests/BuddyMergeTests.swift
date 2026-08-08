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
                      erasedAt: Double? = nil, savedAt: Double = 1000,
                      doneTombs: [String: DoneMark] = [:]) -> SyncSnapshot {
        SyncSnapshot(today: today, history: history, deferred: deferred,
                     settings: settings, tombstones: tombstones, doneTombs: doneTombs,
                     erasedAt: erasedAt, savedAt: savedAt)
    }
    private func dmark(_ v: Int, _ t: Double? = nil) -> DoneMark {
        DoneMark(v: v, t: t ?? Date().timeIntervalSince1970 * 1000)
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

    // A blank active row carries no information and must NEVER survive a merge — that's
    // how a phantom blank reached a second device and falsely tripped lvl2 (2026-07-28).
    // Empty + whitespace-only actives are dropped; done rows and real text are kept.
    // Mirrors the Mac mergeItems filter.
    func testEmptyActiveTaskDroppedFromMerge() {
        let a = snap(today: TodayState(date: "2026-06-19", items: [
            item("real", "keep me"),
            item("blank", ""),
            item("ws", "   "),
            item("done", "finished", .done),
        ]), savedAt: 2000)
        let b = snap(today: TodayState(date: "2026-06-19", items: []), savedAt: 1000)
        let items = BuddyMerge.merge(a, b)?.today?.items ?? []
        XCTAssertNil(items.first { $0.id == "blank" })     // empty active dropped
        XCTAssertNil(items.first { $0.id == "ws" })        // whitespace-only active dropped
        XCTAssertNotNil(items.first { $0.id == "real" })   // real text kept
        XCTAssertNotNil(items.first { $0.id == "done" })   // done row kept unconditionally
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

    // MARK: - The 2026-08-08 resurrection ("I checked off Ghost pricing pages, it keeps coming back")
    //
    // A rollover DROPS completed rows, and pure absence never wins a union — so the peer that
    // never saw the completion re-added its own stale ACTIVE copy every single day. doneTombs
    // is the missing "it left today, on purpose" signal. Byte-parallel to the Mac's tests 23-31.

    /// SYMMETRIC: both devices rolled. One carries the done-mark, the other carried the task
    /// forward still active. The mark wins, in BOTH argument orders.
    func testDoneMarkBeatsPeersStaleCarriedForwardCopy() {
        let day2 = "2026-06-20"
        let a = snap(today: TodayState(date: day2, items: [item("keep", "Ghost Navigation")]),
                     savedAt: 2000, doneTombs: ["gp": dmark(4)])
        let b = snap(today: TodayState(date: day2, items: [
            item("keep", "Ghost Navigation"), item("gp", "Ghost pricing pages", .neutral, 3)]), savedAt: 1000)
        XCTAssertEqual(ids(BuddyMerge.merge(a, b)), ["keep"])
        XCTAssertEqual(ids(BuddyMerge.merge(b, a)), ["keep"])
    }

    /// ASYMMETRIC (the user's ACTUAL scenario): device A rolled to day2 carrying the task
    /// ACTIVE; device B has not rolled and still holds it DONE on day1. This lands in merge()'s
    /// DIFFERENT-DATE branch, which used to take the later day's list wholesale — no tombstones,
    /// no marks — so the completion was silently undone.
    func testDifferentDateBranchHonoursACompletionOnTheUnrolledDevice() {
        let rolled = snap(today: TodayState(date: "2026-06-20", items: [item("gp", "Ghost pricing pages", .neutral, 3)]), savedAt: 1000)
        let unrolled = snap(today: TodayState(date: "2026-06-19", items: [
            item("gp", "Ghost pricing pages", .done, 4, Date(timeIntervalSince1970: 5000))]), savedAt: 2000)
        XCTAssertEqual(ids(BuddyMerge.merge(rolled, unrolled)), [])
        XCTAssertEqual(ids(BuddyMerge.merge(unrolled, rolled)), [])
        // …and the completed day is still archived, done — nothing is lost, it just isn't live.
        let hist = BuddyMerge.merge(rolled, unrolled)?.history.first { $0.date == "2026-06-19" }
        XCTAssertEqual(hist?.items.first { $0.id == "gp" }?.done, true)
    }

    /// Same wholesale-copy hole, for a plain DELETE.
    func testDifferentDateBranchHonoursTombstones() {
        let rolled = snap(today: TodayState(date: "2026-06-20", items: [item("gone", "deleted elsewhere")]), savedAt: 1000)
        let peer = snap(today: TodayState(date: "2026-06-19", items: [item("other", "x")]),
                        tombstones: ["gone": 9999], savedAt: 2000)
        XCTAssertFalse(ids(BuddyMerge.merge(rolled, peer)).contains("gone"))
        XCTAssertFalse(ids(BuddyMerge.merge(peer, rolled)).contains("gone"))
    }

    /// A done-mark must NOT veto a later UNDO — undo bumps v past the mark. This is exactly
    /// why the mark is version-aware instead of a plain tombstone.
    func testUndoAboveTheMarkSurvives() {
        let day2 = "2026-06-20"
        let a = snap(today: TodayState(date: day2, items: []), savedAt: 1000, doneTombs: ["gp": dmark(4)])
        let b = snap(today: TodayState(date: day2, items: [item("gp", "Ghost pricing pages", .neutral, 5)]), savedAt: 2000)
        XCTAssertEqual(ids(BuddyMerge.merge(a, b)), ["gp"])
        XCTAssertEqual(ids(BuddyMerge.merge(b, a)), ["gp"])
    }

    /// Marks union by HIGHEST version, and survive a round trip through the wire so an
    /// un-upgraded peer echoing the blob back can't drop or weaken them.
    func testDoneMarksTakeHighestVersionAndSurviveTheWire() throws {
        let m = BuddyMerge.merge(snap(savedAt: 2000, doneTombs: ["x": dmark(2)]),
                                 snap(savedAt: 1000, doneTombs: ["x": dmark(7)]))
        XCTAssertEqual(m?.doneTombs["x"]?.v, 7)
        let data = try JSONEncoder().encode(SyncWire(m!))
        let back = try JSONDecoder().decode(SyncWire.self, from: data).toSnapshot()
        XCTAssertEqual(back.doneTombs["x"]?.v, 7)
    }

    /// Done-marks age out at 90 days so the map can't grow forever…
    func testStaleDoneMarksArePruned() {
        let stale = Date().timeIntervalSince1970 * 1000 - 100 * 86_400_000
        let m = BuddyMerge.merge(snap(savedAt: 2000, doneTombs: ["stale": dmark(1, stale), "fresh": dmark(1)]),
                                 snap(savedAt: 1000))
        XCTAssertNil(m?.doneTombs["stale"])
        XCTAssertNotNil(m?.doneTombs["fresh"])
    }

    /// …but a PLAIN tombstone must never be age-pruned. iOS writes them in SECONDS
    /// (timeIntervalSince1970) while the Mac writes MILLISECONDS, so an age check reads every
    /// iPhone-minted tombstone as 1970 and deletes it — resurrecting every task ever deleted on
    /// the phone. Pinned here and on the Mac so it can't come back.
    func testSecondsUnitTombstoneIsNeverAgedOut() {
        let m = BuddyMerge.merge(snap(tombstones: ["iosDel": 1_783_625_135.289], savedAt: 2000),
                                 snap(today: TodayState(date: "2026-06-19", items: [item("iosDel", "deleted on iPhone")]), savedAt: 1000))
        XCTAssertNotNil(m?.tombstones["iosDel"])
        XCTAssertFalse(ids(m).contains("iosDel"))
    }

    /// A mark with no clock (t == 0) is kept — "no timestamp" is not "expired".
    func testDoneMarkWithoutTimestampIsKept() {
        let m = BuddyMerge.merge(snap(savedAt: 2000, doneTombs: ["nc": DoneMark(v: 2, t: 0)]), snap(savedAt: 1000))
        XCTAssertNotNil(m?.doneTombs["nc"])
    }

    /// HISTORY: two devices order the same day differently, so the old positional ids
    /// (h-<date>-<i>) collided and merged two DIFFERENT tasks into one — destroying a text and
    /// handing the survivor the other's checkmark. Real item ids fix it.
    func testHistoryMergesByRealIdNotPosition() {
        let a = Day(date: "2026-06-19", weekday: "Friday", items: [
            DayItem(id: "gp", text: "Ghost pricing pages", done: true, ord: 0),
            DayItem(id: "nav", text: "Ghost Navigation", done: false, ord: 1)])
        let b = Day(date: "2026-06-19", weekday: "Friday", items: [
            DayItem(id: "nav", text: "Ghost Navigation", done: false, ord: 0),
            DayItem(id: "gp", text: "Ghost pricing pages", done: true, ord: 1)])
        let m = BuddyMerge.mergeHistRecord(a, b)
        XCTAssertEqual(m.items.count, 2)
        XCTAssertEqual(m.items.first { $0.id == "gp" }?.done, true)
        XCTAssertEqual(m.items.first { $0.id == "nav" }?.done, false)
        // symmetric
        let r = BuddyMerge.mergeHistRecord(b, a)
        XCTAssertEqual(m.items.map { $0.id }, r.items.map { $0.id })
    }

    /// A day can legitimately hold a DONE "Foo" and an ACTIVE "Foo" (clampActive only dedupes
    /// ACTIVE titles). Both must survive — a text-keyed merge would delete one.
    func testHistoryKeepsDoneAndActiveSameTitleAsTwoRows() {
        let rec = BuddyMerge.todayToHistoryRecord(TodayState(date: "2026-06-19", items: [
            item("f1", "Email Sam", .done, 2, Date(timeIntervalSince1970: 100)),
            item("f2", "Email Sam")]))!
        let m = BuddyMerge.mergeHistRecord(rec, rec)
        XCTAssertEqual(m.items.count, 2)
        XCTAssertEqual(m.items.filter { $0.done }.count, 1)
    }

    /// Archived rows keep the REAL item id + an order (so the Mac and iOS agree row-for-row).
    func testHistoryRecordKeepsRealItemIdAndOrder() {
        let rec = BuddyMerge.todayToHistoryRecord(TodayState(date: "2026-06-19", items: [
            item("aaa", "first"), item("bbb", "second")]))!
        XCTAssertEqual(rec.items.map { $0.id }, ["aaa", "bbb"])
        XCTAssertEqual(rec.items.map { $0.order }, [0, 1])
    }

    /// `ord` must ROUND-TRIP the wire — dropping it would silently strip the Mac's ordering
    /// on every iOS pass.
    func testHistoryOrdRoundTripsTheWire() throws {
        let s = snap(history: [Day(date: "2026-06-19", weekday: "Friday",
                                   items: [DayItem(id: "z", text: "z", done: false, ord: 3)])])
        let data = try JSONEncoder().encode(SyncWire(s))
        let back = try JSONDecoder().decode(SyncWire.self, from: data).toSnapshot()
        XCTAssertEqual(back.history.first?.items.first?.ord, 3)
    }

    // MARK: - Second-review findings (all of these passed the first suite, and were all real)

    /// EQUAL v is a genuine conflict, not a veto. `>=` annihilated a concurrent rename with no
    /// tombstone, no history row and no trace at all.
    func testEqualVersionConcurrentEditIsNotAnnihilated() {
        let day2 = "2026-06-20"
        let a = snap(today: TodayState(date: day2, items: []), savedAt: 2000, doneTombs: ["gp": dmark(8)])
        let b = snap(today: TodayState(date: day2, items: [item("gp", "renamed on the phone", .neutral, 8)]), savedAt: 1000)
        XCTAssertEqual(ids(BuddyMerge.merge(a, b)), ["gp"])
        XCTAssertEqual(ids(BuddyMerge.merge(b, a)), ["gp"])
    }

    /// merge() must be a PURE function of its inputs. It emits done-marks, and a clock read there
    /// makes two devices produce different maps from identical inputs — which churns contentKey
    /// and makes them push at each other forever. The stamp is midnight of the ARCHIVED DAY.
    func testMergeEmittedMarksAreClockFreeAndSymmetric() {
        let rolled = snap(today: TodayState(date: "2026-06-20", items: [item("gp", "x", .neutral, 3)]), savedAt: 1000)
        let done = snap(today: TodayState(date: "2026-06-19", items: [
            item("gp", "x", .done, 4, Date(timeIntervalSince1970: 5000))]), savedAt: 2000)
        let m1 = BuddyMerge.merge(rolled, done), m2 = BuddyMerge.merge(done, rolled)
        XCTAssertEqual(m1?.doneTombs["gp"]?.t, BuddyMerge.dayStamp("2026-06-19"))
        XCTAssertEqual(m1?.doneTombs["gp"]?.t, m2?.doneTombs["gp"]?.t)
        XCTAssertEqual(m1?.doneTombs["gp"]?.v, m2?.doneTombs["gp"]?.v)
        // …and byte-identical on both platforms: the Mac stamps the same way.
        XCTAssertEqual(BuddyMerge.dayStamp("2026-06-19"), 1_781_827_200_000)   // == Date.parse(...) on the Mac
    }

    /// Retention is measured from the NEWEST mark, not from Date(). A clock-based cutoff made
    /// eviction depend on WHEN you merged: two devices minutes apart disagree at the boundary,
    /// each re-supplies the mark by union, and they ping-pong until the skew passes.
    func testMarkRetentionIsRelativeToNewestMarkNotTheClock() {
        let m = BuddyMerge.merge(
            snap(savedAt: 2000, doneTombs: ["old": dmark(1, 1000),
                                            "recent": dmark(1, 1000 + BuddyMerge.markRetention + 1)]),
            snap(savedAt: 1000))
        XCTAssertNil(m?.doneTombs["old"])
        XCTAssertNotNil(m?.doneTombs["recent"])
    }

    /// A rollover pairs every done-mark with a PLAIN tombstone, so a peer on an OLDER build (which
    /// has never heard of doneTombs but does honour tombstones) drops the row instead of re-adding
    /// it and push-fighting. The mark is what lets a later undo escape that veto — and a user
    /// DELETE, which writes no mark, stays unconditional.
    func testRollbackTombstonePairing() {
        let day2 = "2026-06-20"
        let archived = snap(today: TodayState(date: day2, items: []), tombstones: ["gp": 1000],
                            savedAt: 2000, doneTombs: ["gp": dmark(4, 1000)])
        let stale = snap(today: TodayState(date: day2, items: [item("gp", "Ghost pricing pages", .neutral, 3)]), savedAt: 1000)
        XCTAssertEqual(ids(BuddyMerge.merge(archived, stale)), [])
        XCTAssertEqual(ids(BuddyMerge.merge(stale, archived)), [])

        let undone = snap(today: TodayState(date: day2, items: [item("gp", "Ghost pricing pages", .neutral, 5)]), savedAt: 1000)
        XCTAssertEqual(ids(BuddyMerge.merge(archived, undone)), ["gp"])
        XCTAssertEqual(ids(BuddyMerge.merge(undone, archived)), ["gp"])

        let deleted = snap(today: TodayState(date: day2, items: []), tombstones: ["gp": 1000], savedAt: 2000)
        XCTAssertEqual(ids(BuddyMerge.merge(deleted, undone)), [])
        XCTAssertEqual(ids(BuddyMerge.merge(undone, deleted)), [])
    }

    /// The DoneMark decoder must fail CLOSED, exactly like the Mac. Failing open turns junk into
    /// `v:1` — which vetoes any item at v:1, i.e. a task you just typed — and `t:0`, never pruned.
    func testDoneMarkDecoderFailsClosedOnJunk() throws {
        let junk = """
        {"a":null,"b":{},"c":[1,2],"d":{"t":1},"e":{"v":0,"t":1},"f":{"v":-2},"g":"4","h":0,"i":-3,
         "ok":{"v":4,"t":99},"bare":7,"negT":{"v":4,"t":-5}}
        """
        let raw = try JSONDecoder().decode([String: JSONValue].self, from: Data(junk.utf8))
        let marks = BuddyMerge.sanitizeMarks(raw)
        for bad in ["a", "b", "c", "d", "e", "f", "g", "h", "i"] {
            XCTAssertNil(marks[bad], "\(bad) should have been dropped, got \(String(describing: marks[bad]))")
        }
        XCTAssertEqual(marks["ok"], DoneMark(v: 4, t: 99))
        XCTAssertEqual(marks["bare"], DoneMark(v: 7, t: 0))
        XCTAssertEqual(marks["negT"]?.t, 0, "a negative t must normalise to 0, like the Mac")
    }

    /// A peer that strips `ord` must not flatten a real order to zero. min() with a fallback 0
    /// destroyed the day's planner order permanently, even after the peer updated.
    func testStrippedOrdCannotFlattenTheDaysOrder() {
        let full = Day(date: "2026-06-19", weekday: "Friday", items: [
            DayItem(id: "zzz", text: "first", done: false, ord: 0),
            DayItem(id: "aaa", text: "second", done: false, ord: 1)])
        let stripped = Day(date: "2026-06-19", weekday: "Friday", items: [
            DayItem(id: "zzz", text: "first", done: false),
            DayItem(id: "aaa", text: "second", done: false)])
        let m = BuddyMerge.mergeHistRecord(full, stripped)
        XCTAssertEqual(m.items.map { $0.id }, ["zzz", "aaa"])
        XCTAssertEqual(m.items.map { $0.ord }, [0, 1])
    }

    /// The legacy positional-id parse must match the Mac's regex, which requires a NON-EMPTY
    /// middle segment — "h-5" scores 0 on both, not 0 here and 5 there.
    func testLegacyOrderParseMatchesTheMacRegex() {
        XCTAssertEqual(DayItem(id: "h-2026-06-19-10", text: "", done: false).order, 10)
        XCTAssertEqual(DayItem(id: "h-5", text: "", done: false).order, 0)
        XCTAssertEqual(DayItem(id: "zzz-foreign", text: "", done: false).order, 0)
    }
}
