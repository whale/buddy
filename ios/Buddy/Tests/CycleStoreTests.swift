import XCTest
@testable import Buddy

// Active-task interaction logic (parity item 2 "focused/now" + item 5 caps).
final class CycleStoreTests: XCTestCase {
    private func neutral(_ id: String) -> BuddyTask { BuddyTask(id: id, text: id, state: .neutral) }

    func testCycleNeutralToFocusedBumpsVersion() {
        let s = BuddyStore()
        s.today = TodayState(date: BuddyStore.localDate(), items: [neutral("a")], morningDone: true)
        let vBefore = s.today.items[0].v
        let completed = s.cycle(s.today.items[0])
        XCTAssertFalse(completed)                          // focusing isn't completing
        XCTAssertEqual(s.today.items[0].state, .focused)
        XCTAssertGreaterThan(s.today.items[0].v, vBefore)  // change bumps the merge version
    }

    func testOnlyOneFocusedAtATime() {
        let s = BuddyStore()
        s.today = TodayState(date: BuddyStore.localDate(), items: [neutral("a"), neutral("b")], morningDone: true)
        _ = s.cycle(s.today.items[0])    // a → focused
        _ = s.cycle(s.today.items[1])    // b → focused, a must clear
        XCTAssertEqual(s.today.items.first { $0.id == "a" }?.state, .neutral)
        XCTAssertEqual(s.today.items.first { $0.id == "b" }?.state, .focused)
    }

    func testCycleFocusedToDoneCompletes() {
        let s = BuddyStore()
        var t = neutral("a"); t.state = .focused
        s.today = TodayState(date: BuddyStore.localDate(), items: [t], morningDone: true)
        let completed = s.cycle(s.today.items[0])
        XCTAssertTrue(completed)                           // → fires the celebration
        XCTAssertEqual(s.today.items[0].state, .done)
        XCTAssertNotNil(s.today.items[0].doneAt)
    }

    func testAddBlockedAtHardCap() {
        let s = BuddyStore()
        s.today = TodayState(date: BuddyStore.localDate(),
                             items: (0..<6).map { neutral("t\($0)") }, morningDone: true)
        XCTAssertTrue(s.atHardCap)
        XCTAssertNil(s.addTask())                          // no 7th active task
    }


    func testWakeDeferredBlockedAtHardCap() {
        let s = BuddyStore()
        s.today = TodayState(date: BuddyStore.localDate(),
                             items: (0..<6).map { neutral("t\($0)") }, morningDone: true)
        s.deferred = [DeferredTask(id: "f1", text: "Future task", wake: "2026-07-09")]
        s.wakeDeferredTask(id: "f1")
        XCTAssertEqual(s.activeCount, BuddyStore.hardCap)
        XCTAssertNil(s.deferred.first?.sent)
    }

    // Check-off circle (parity item A): complete() marks done from any state.
    func testCompleteDirectlyMarksDone() {
        let s = BuddyStore()
        s.today = TodayState(date: BuddyStore.localDate(), items: [neutral("a")], morningDone: true)
        XCTAssertTrue(s.complete(s.today.items[0]))           // transition into done → celebrate
        XCTAssertEqual(s.today.items[0].state, .done)
        XCTAssertNotNil(s.today.items[0].doneAt)
        XCTAssertFalse(s.complete(s.today.items[0]))          // already done → no new transition
    }

    // Erase all data (parity item 4) — clears everything and stamps the sync barrier.
    func testEraseAllClearsAndStampsBarrier() {
        let s = BuddyStore()
        s.today = TodayState(date: BuddyStore.localDate(), items: [neutral("a")], morningDone: true)
        s.history = [Day(date: "2020-01-01", weekday: "Wednesday",
                         items: [DayItem(id: "h-2020-01-01-0", text: "x", done: true)])]
        s.eraseAll()
        XCTAssertTrue(s.today.items.isEmpty)
        XCTAssertTrue(s.history.isEmpty)
        XCTAssertNotNil(s.erasedAt)        // barrier so a real wipe wins over a stale sync push
    }

    // MARK: - Boss Mode (sweep done off the list) — Mac parity + sync (whale 2026-07-20)
    private func doneTask(_ id: String) -> BuddyTask { BuddyTask(id: id, text: id, state: .done, doneAt: Date()) }

    func testBossReadyThresholdIsFive() {
        let s = BuddyStore()
        s.today = TodayState(date: BuddyStore.localDate(), items: (0..<4).map { doneTask("d\($0)") }, morningDone: true)
        XCTAssertFalse(s.bossReady)                         // 4 done → no sweep offer
        s.today.items.append(doneTask("d4"))
        XCTAssertTrue(s.bossReady)                          // 5 → Boss row appears
    }

    func testBossMoveSweepsOffListButKeepsInDoneTab() {
        let s = BuddyStore()
        s.today = TodayState(date: BuddyStore.localDate(), items: (0..<5).map { doneTask("d\($0)") }, morningDone: true)
        let vBefore = s.today.items[0].v
        s.bossMove()
        XCTAssertTrue(s.listDoneTasks.isEmpty, "swept off the Today list")
        XCTAssertEqual(s.doneTasks.count, 5, "still in state → still in the Done tab")
        XCTAssertTrue(s.today.items.allSatisfy { $0.isCleared })
        XCTAssertGreaterThan(s.today.items[0].v, vBefore, "v bumped so the sweep syncs")
        XCTAssertFalse(s.bossReady, "no visible pile left")
    }

    func testUncompleteClearsClearedAt() {
        let s = BuddyStore()
        var t = doneTask("a"); t.clearedAt = Date()
        s.today = TodayState(date: BuddyStore.localDate(), items: [t], morningDone: true)
        s.restoreTask(id: "a")
        XCTAssertNil(s.today.items[0].clearedAt, "un-done → no longer swept")
        XCTAssertEqual(s.today.items[0].state, .neutral)
    }

    // clearedAt lives in per-item extras → it round-trips the wire (so it syncs), and a v-bumped
    // cleared copy wins the merge, carrying clearedAt (an action on either device mirrors).
    func testClearedAtRidesTheWireAndMerge() {
        var t = doneTask("a"); t.clearedAt = Date(timeIntervalSince1970: 1_750_000_000); t.v = 2
        let mine = SyncSnapshot(today: TodayState(date: "d", items: [t]), history: [], deferred: [],
                                settings: .default, tombstones: [:], erasedAt: nil, savedAt: 1000)
        let round = SyncWire(mine).toSnapshot()
        XCTAssertNotNil(round.today?.items.first?.clearedAt, "clearedAt survives the wire round-trip")
        var stale = doneTask("a"); stale.v = 1
        let other = SyncSnapshot(today: TodayState(date: "d", items: [stale]), history: [], deferred: [],
                                 settings: .default, tombstones: [:], erasedAt: nil, savedAt: 900)
        XCTAssertNotNil(BuddyMerge.merge(mine, other)?.today?.items.first?.clearedAt,
                        "the cleared v2 copy wins the merge → clearedAt propagates to the peer")
    }

    // Invariant guard: clearedAt is excluded from contentKey, so the sweep only syncs because it
    // v-bumps. If a future change sets clearedAt WITHOUT bumping v, this fails (it'd never push).
    func testBossMoveChangesContentKeySoItSyncs() {
        let s = BuddyStore()
        s.today = TodayState(date: BuddyStore.localDate(), items: (0..<5).map { doneTask("d\($0)") }, morningDone: true)
        let before = BuddySync.contentKey(s.snapshot())
        s.bossMove()
        XCTAssertNotEqual(before, BuddySync.contentKey(s.snapshot()), "the sweep must change contentKey → it syncs")
    }

    // The cross-platform requirement: a boss-move on a device whose GLOBAL savedAt is OLDER must
    // still win — per-item v beats global savedAt. (The wire test above only covered newer savedAt.)
    func testClearedItemWinsEvenOnOlderDevice() {
        var cleared = doneTask("a"); cleared.clearedAt = Date(timeIntervalSince1970: 1_750_000_000); cleared.v = 2
        let older = SyncSnapshot(today: TodayState(date: "d", items: [cleared]), history: [], deferred: [],
                                 settings: .default, tombstones: [:], erasedAt: nil, savedAt: 100)    // OLDER save
        let newer = SyncSnapshot(today: TodayState(date: "d", items: [doneTask("a")]), history: [], deferred: [],
                                 settings: .default, tombstones: [:], erasedAt: nil, savedAt: 9999)   // NEWER save, v1
        XCTAssertNotNil(BuddyMerge.merge(newer, older)?.today?.items.first?.clearedAt,
                        "higher item-v wins over global savedAt → the sweep propagates from the older device")
    }

    // MARK: - Rollover identity (the 2026-08-08 resurrection, store side)

    /// Carry-forward used to re-mint every task (new id, v back to 1), so two devices minted two
    /// DIFFERENT ids for the same task each morning and a union-merge could not tell a carry-over
    /// from a task you just typed. Unfinished rows must now carry forward AS THEMSELVES.
    func testRolloverCarriesUnfinishedForwardWithSameIdAndVersion() {
        let s = BuddyStore()
        var carried = BuddyTask(id: "keep-me", text: "carry me", state: .neutral)
        carried.v = 4
        s.today = TodayState(date: "2020-01-01", items: [carried], morningDone: true)
        s.history = []
        XCTAssertTrue(s.performRolloverIfNeeded())
        XCTAssertEqual(s.today.items.map { $0.id }, ["keep-me"])
        XCTAssertEqual(s.today.items.first?.v, 4)
    }

    /// A completed row leaves Today for good — and must say so on the wire, or the peer that
    /// never saw the completion re-adds its own active copy on the next merge.
    func testRolloverLeavesADoneMarkForCompletedTasks() {
        let s = BuddyStore()
        var done = BuddyTask(id: "gp", text: "Ghost pricing pages", state: .done,
                             doneAt: Date(timeIntervalSince1970: 100))
        done.v = 3
        s.today = TodayState(date: "2020-01-01", items: [done], morningDone: true)
        s.history = []
        XCTAssertTrue(s.performRolloverIfNeeded())
        XCTAssertFalse(s.today.items.contains { $0.id == "gp" })
        XCTAssertEqual(s.doneTombs["gp"]?.v, 3)
    }

    /// The archived record keeps the REAL item id, not a positional one.
    func testRolloverArchivesWithRealItemIds() {
        let s = BuddyStore()
        s.today = TodayState(date: "2020-01-01", items: [neutral("aaa"), neutral("bbb")], morningDone: true)
        s.history = []
        XCTAssertTrue(s.performRolloverIfNeeded())
        XCTAssertEqual(s.history.first { $0.date == "2020-01-01" }?.items.map { $0.id }, ["aaa", "bbb"])
    }

    /// The restore paths mint a fresh item from the TEXT alone, so a done-marked row must never
    /// be offered back — the second resurrection route.
    func testRestoreSkipsDoneMarkedRows() {
        let s = BuddyStore()
        var done = BuddyTask(id: "gp", text: "Ghost pricing pages", state: .done,
                             doneAt: Date(timeIntervalSince1970: 100))
        done.v = 2
        s.today = TodayState(date: "2020-01-01", items: [done, neutral("live")], morningDone: true)
        s.history = []
        _ = s.performRolloverIfNeeded()
        // The archived row for "gp" is done anyway; force the corrupted shape (done flag lost)
        // to prove the MARKER is what stops it, not the flag.
        if let idx = s.history.firstIndex(where: { $0.date == "2020-01-01" }),
           let row = s.history[idx].items.firstIndex(where: { $0.id == "gp" }) {
            s.history[idx].items[row].done = false
        }
        XCTAssertFalse(s.lastListForRestore().contains("Ghost pricing pages"))
    }

    // MARK: - Stranded untitled rows (field report 2026-08-09, Mac; reachable on iOS too)

    /// A blank row counts toward the hard cap on purpose — it is a slot you are using. But one
    /// that gets STRANDED silently costs a task slot: five visible tasks and no way to add a sixth.
    func testStrandedBlankRowIsSweptAndFreesItsCapSlot() {
        let s = BuddyStore()
        s.today = TodayState(date: BuddyStore.localDate(), items:
            (0..<5).map { neutral("t\($0)") } + [BuddyTask(id: "ghost", text: "", state: .neutral)],
            morningDone: true)
        XCTAssertEqual(s.activeCount, 6)
        XCTAssertTrue(s.atHardCap)          // the user sees five, the cap says six
        s.sweepStrandedBlanks()
        XCTAssertEqual(s.activeCount, 5)
        XCTAssertFalse(s.atHardCap)
        XCTAssertFalse(s.today.items.contains { $0.id == "ghost" })
    }

    /// …but the row you are TYPING into is blank for a moment too, and must never be swept.
    func testRowBeingEditedIsNeverSwept() {
        let s = BuddyStore()
        s.today = TodayState(date: BuddyStore.localDate(),
                             items: [neutral("a"), BuddyTask(id: "fresh", text: "", state: .neutral)],
                             morningDone: true)
        s.isEditing = true
        s.sweepStrandedBlanks()
        XCTAssertTrue(s.today.items.contains { $0.id == "fresh" })
    }
}
