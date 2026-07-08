import XCTest
@testable import Buddy

// Tests for the morning planner + day-rollover carry-over (parity item 1).
// These pin the store behavior the MorningView depends on, so a future change
// that breaks "yesterday's unfinished tasks load into the morning" fails loudly.
final class MorningStoreTests: XCTestCase {

    private func task(_ id: String, _ text: String, _ st: TaskState = .neutral) -> BuddyTask {
        BuddyTask(id: id, text: text, state: st)
    }

    // MARK: morning flag

    func testCompleteMorningMarksPlanned() {
        let s = BuddyStore()
        s.today = TodayState(date: BuddyStore.localDate(), items: [], morningDone: false)
        XCTAssertTrue(s.needsMorning)
        s.completeMorning()
        XCTAssertTrue(s.today.morningDone)
        XCTAssertFalse(s.needsMorning)
    }

    func testSkipMorningMarksPlanned() {
        let s = BuddyStore()
        s.today = TodayState(date: BuddyStore.localDate(), items: [], morningDone: false)
        s.skipMorning()
        XCTAssertTrue(s.today.morningDone)
        XCTAssertFalse(s.needsMorning)
    }

    // MARK: rollover carry-over (the behavior the user explicitly wants)

    func testRolloverCarriesUnfinishedAndShowsMorning() {
        let s = BuddyStore()
        s.history = []
        s.today = TodayState(date: "2020-01-01", items: [
            task("a", "done one", .done), task("b", "undone one"), task("c", "undone two")
        ], morningDone: true)                                   // yesterday had been planned

        let rolled = s.performRolloverIfNeeded()

        XCTAssertTrue(rolled)
        XCTAssertEqual(s.today.date, BuddyStore.localDate())    // advanced to today
        XCTAssertFalse(s.today.morningDone)                     // new day → morning will show
        // only the UNFINISHED tasks carry forward, in order
        XCTAssertEqual(s.today.items.map { $0.text }, ["undone one", "undone two"])
        XCTAssertTrue(s.today.items.allSatisfy { $0.state == .neutral })
        // yesterday archived in full (done + undone), with stable h-<date>-<i> ids
        XCTAssertEqual(s.history.first?.date, "2020-01-01")
        XCTAssertEqual(s.history.first?.items.count, 3)
        XCTAssertEqual(s.history.first?.items.first?.id, "h-2020-01-01-0")
    }

    func testRolloverCarriesAllUnfinishedUpToHardCap() {
        let s = BuddyStore()
        s.history = []
        s.today = TodayState(date: "2020-01-01",
                             items: (0..<7).map { task("t\($0)", "task \($0)") },  // 7 unfinished
                             morningDone: true)
        _ = s.performRolloverIfNeeded()
        XCTAssertEqual(s.today.items.count, BuddyStore.hardCap)  // carry the full list (6), not 5
    }

    // Slice 2: the already-archived branch no longer DROPS the live items (that was
    // data loss when the other device rolled the day first) — it merges them into the
    // existing record and still carries the unfinished ones forward, like the Mac.
    func testRolloverIsIdempotentAcrossDuplicateDates() {
        let s = BuddyStore()
        s.today = TodayState(date: "2020-01-01", items: [task("a", "x")], morningDone: true)
        s.history = [Day(date: "2020-01-01", weekday: "Wednesday",
                         items: [DayItem(id: "h-2020-01-01-0", text: "x", done: false)])]  // already archived
        _ = s.performRolloverIfNeeded()
        XCTAssertEqual(s.history.filter { $0.date == "2020-01-01" }.count, 1)  // no double-archive
        // unfinished "x" carries forward into the fresh day (fresh id, not dropped)
        XCTAssertEqual(s.today.items.map { $0.text }, ["x"])
        XCTAssertEqual(s.today.date, BuddyStore.localDate())
    }

    // Slice 2: already-archived + live items that DIFFER from the record → the live list
    // merges into the record (done-wins, union by positional id) instead of vanishing.
    func testRolloverMergesLiveItemsIntoExistingRecord() {
        let s = BuddyStore()
        s.today = TodayState(date: "2020-01-01", items: [
            task("a", "x", .done),          // live copy finished x → done-wins over the record
            task("b", "y")                  // live-only second task → appended to the record
        ], morningDone: true)
        s.history = [Day(date: "2020-01-01", weekday: "Wednesday",
                         items: [DayItem(id: "h-2020-01-01-0", text: "x", done: false)])]
        _ = s.performRolloverIfNeeded()
        let rec = s.history.first { $0.date == "2020-01-01" }
        XCTAssertEqual(rec?.items.count, 2)
        XCTAssertEqual(rec?.items.first { $0.id == "h-2020-01-01-0" }?.done, true)   // done-wins
        XCTAssertEqual(rec?.items.first { $0.id == "h-2020-01-01-1" }?.text, "y")    // live-only kept
        // and the unfinished "y" carries forward
        XCTAssertEqual(s.today.items.map { $0.text }, ["y"])
    }

    func testEmptyYesterdayArchivesNothingButStillShowsMorning() {
        let s = BuddyStore()
        s.history = []
        s.today = TodayState(date: "2020-01-01", items: [], morningDone: true)
        let rolled = s.performRolloverIfNeeded()
        XCTAssertTrue(rolled)
        XCTAssertTrue(s.history.isEmpty)            // nothing to archive
        XCTAssertFalse(s.today.morningDone)         // fresh day still shows the planner
    }

    // MARK: persistence shape

    func testMorningDoneSurvivesCodableRoundTrip() throws {
        let t = TodayState(date: "2026-06-20", items: [], morningDone: true)
        let back = try JSONDecoder().decode(TodayState.self, from: JSONEncoder().encode(t))
        XCTAssertTrue(back.morningDone)
        // a legacy blob without the field decodes to false (tolerant), not a crash
        let legacy = try JSONDecoder().decode(TodayState.self,
                                              from: Data(#"{"date":"2026-06-20","items":[]}"#.utf8))
        XCTAssertFalse(legacy.morningDone)
    }
}
