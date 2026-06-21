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
}
