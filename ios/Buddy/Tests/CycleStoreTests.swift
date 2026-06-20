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
}
