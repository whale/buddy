import XCTest
@testable import Buddy

// History sheet rules mirrored from the Mac: tab counts, Done paging (30 items), day headings,
// and the Future shrink-to-fit.
final class HistoryModelTests: XCTestCase {
    private let cal = Calendar.current
    private func ds(_ back: Int, from now: Date = Date()) -> String {
        BuddyStore.localDate(cal.date(byAdding: .day, value: -back, to: now)!)
    }
    private func day(_ back: Int, done: Int, undone: Int = 0, blank: Int = 0) -> Day {
        let d = ds(back)
        var items = (0..<done).map { DayItem(id: "\(d)-d\($0)", text: "D\(back)-\($0)", done: true) }
        items += (0..<undone).map { DayItem(id: "\(d)-u\($0)", text: "U\($0)", done: false) }
        items += (0..<blank).map { DayItem(id: "\(d)-b\($0)", text: "  ", done: true) }
        return Day(date: d, weekday: "", items: items)
    }
    private func doneToday(_ n: Int) -> [BuddyTask] {
        (0..<n).map { BuddyTask(id: "t\($0)", text: "T\($0)", state: .done, doneAt: Date()) }
    }

    // MARK: counts

    func testFutureCountExcludesSentAndBlank() {
        let d = [DeferredTask(id: "a", text: "A", wake: ""),
                 DeferredTask(id: "b", text: "B", wake: "", sent: true, sentTid: "x"),
                 DeferredTask(id: "c", text: "   ", wake: ""),
                 DeferredTask(id: "e", text: "E", wake: "")]
        XCTAssertEqual(HistoryModel.futureCount(d), 2)
    }

    func testDoneCountIsTodayPlusEveryArchivedDoneWithText() {
        let h = [day(1, done: 3, undone: 2, blank: 1), day(40, done: 2)]
        XCTAssertEqual(HistoryModel.doneCount(todayDone: doneToday(4), history: h), 4 + 3 + 2)
    }

    // The count must equal what the list shows — a today-dated archive record is in neither.
    func testDoneCountMatchesTheListExactly() {
        let h = [day(0, done: 3), day(1, done: 2, blank: 1), day(50, done: 4)]
        let page = HistoryModel.donePage(todayDone: doneToday(2), history: h, shown: 1000)
        XCTAssertEqual(HistoryModel.doneCount(todayDone: doneToday(2), history: h),
                       page.groups.flatMap(\.lines).count)
        XCTAssertEqual(HistoryModel.doneCount(todayDone: doneToday(2), history: h), 8)
    }

    func testBinarySearchPicksTheSameStepAsALinearScan() {
        for n in 0...20 {
            let texts = (0..<n).map { "Item \($0)" }
            let r = FutureFit.compute(texts: texts, sentCount: 1, sentH: 46, height: 490, width: 380, measure: oneLine)
            var linear = FutureFit.steps - 1
            for k in 0..<FutureFit.steps {
                let total = (texts + ["Add +"]).map { max(FutureFit.floorH(k, sentH: 46), oneLine($0, FutureFit.font(k), 316) + 2 * FutureFit.vpad(k)) }.reduce(0, +)
                if total <= 490 - 46 - CGFloat(n + 1) { linear = k; break }
            }
            XCTAssertEqual(r.step, linear, "n=\(n)")
        }
    }

    // MARK: Done paging

    func testFirstPageIs30WithTodayCountingAndCutsMidDay() {
        let h = (1...10).map { day($0, done: 4) }                    // 40 archived
        let page = HistoryModel.donePage(todayDone: doneToday(6), history: h, shown: 30)
        let lines = page.groups.flatMap(\.lines)
        XCTAssertEqual(lines.count, 30)
        XCTAssertEqual(page.groups.first?.header, "Today")
        XCTAssertEqual(page.groups.first?.lines.count, 6)
        XCTAssertEqual(page.groups.last?.lines.count, 4)              // 6 + 4×6 = 30 → day 6 complete
        XCTAssertTrue(page.hasMore)
        // Newest first.
        XCTAssertEqual(page.groups.dropFirst().map(\.id), (1...6).map { ds($0) })
    }

    func testPageCutsInsideADay() {
        let page = HistoryModel.donePage(todayDone: doneToday(1), history: [day(1, done: 5), day(2, done: 5)], shown: 8)
        XCTAssertEqual(page.groups.map { $0.lines.count }, [1, 5, 2])  // day 2 cut mid-day
        XCTAssertTrue(page.hasMore)
    }

    func testLoadMoreAddsNextThirtyAndEndsCleanly() {
        let h = (1...10).map { day($0, done: 4) }
        let p2 = HistoryModel.donePage(todayDone: doneToday(6), history: h, shown: 60)
        XCTAssertEqual(p2.groups.flatMap(\.lines).count, 46)
        XCTAssertFalse(p2.hasMore)
    }

    func testExactlyThirtyHasNoMore() {
        let page = HistoryModel.donePage(todayDone: [], history: [day(1, done: 30)], shown: 30)
        XCTAssertFalse(page.hasMore)
    }

    func testPagingSkipsUndoneBlankAndTodayDatedRecords() {
        let h = [day(0, done: 3), day(1, done: 1, undone: 3, blank: 2)]  // day(0) = today's archive → not shown
        let page = HistoryModel.donePage(todayDone: [], history: h, shown: 30)
        XCTAssertEqual(page.groups.map { $0.lines.count }, [1])
    }

    // MARK: headings

    func testHeadingWithinAWeekIsWeekdayOlderAddsDate() {
        let now = DateComponents(calendar: cal, year: 2026, month: 10, day: 1, hour: 12).date!   // a Thursday
        XCTAssertEqual(HistoryModel.dayHeading(date: ds(1, from: now), now: now), "Wednesday")
        XCTAssertEqual(HistoryModel.dayHeading(date: ds(6, from: now), now: now), "Friday")
        // Exactly 7 days back is NOT newer than weekAgo → gets the date (Mac: r.date > weekAgo).
        XCTAssertEqual(HistoryModel.dayHeading(date: ds(7, from: now), now: now), "Thursday, Sep 24")
        XCTAssertEqual(HistoryModel.dayHeading(date: ds(9, from: now), now: now), "Tuesday, Sep 22")
    }

    // MARK: Future shrink-to-fit (fake measurer: one line = 0.8 × font, so it's deterministic)

    private func oneLine(_ s: String, _ f: CGFloat, _ w: CGFloat) -> CGFloat { s.hasPrefix("LONG") ? f * 3.5 : f * 0.8 }
    private func fit(_ n: Int, H: CGFloat = 490, held: Int? = nil, texts: [String]? = nil) -> FutureFit.Result {
        FutureFit.compute(texts: texts ?? (0..<n).map { "Item \($0)" }, sentCount: 0, sentH: 46,
                          height: H, width: 380, heldStep: held, measure: oneLine)
    }

    func testFewItemsStayBigAndFillEqually() {
        let r = fit(2)
        XCTAssertEqual(r.step, 0)
        XCTAssertEqual(r.font, 24)
        XCTAssertFalse(r.overflow)
        XCTAssertEqual(Set(r.heights).count, 1)                         // equal (incl. Add)
        XCTAssertGreaterThan(r.heights[0], 110)                         // stretched to fill
        XCTAssertEqual(r.heights.reduce(0, +), 490 - 2, accuracy: 3)    // fills the panel (minus dividers)
    }

    func testMoreItemsShrinkBeforeScrolling() {
        let r = fit(7)
        XCTAssertGreaterThan(r.step, 0)
        XCTAssertLessThan(r.step, FutureFit.steps - 1)
        XCTAssertFalse(r.overflow)
        XCTAssertLessThan(r.font, 24)
        XCTAssertGreaterThanOrEqual(r.heights.min()!, r.floorH)
        // Largest step that fits: one step bigger would NOT fit.
        let bigger = FutureFit.floorH(r.step - 1, sentH: 46)
        XCTAssertGreaterThan(bigger * 8, 490 - 7)
    }

    func testTooManyScrollsAtSmallestStep() {
        let r = fit(16)
        XCTAssertEqual(r.step, FutureFit.steps - 1)
        XCTAssertTrue(r.overflow)
        XCTAssertEqual(r.font, FutureFit.fontMin)
        XCTAssertEqual(r.floorH, 46)                                    // floor = the sent-row height
        XCTAssertEqual(r.heights.last, 46)                              // pinned Add at the floor
    }

    func testHeldStepIsKeptWhileEditing() {
        XCTAssertEqual(fit(2, held: 5).step, 5)
        XCTAssertEqual(fit(16, held: 0).step, 0)
    }

    func testTallTextGrowsOnlyItsOwnRow() {
        let r = fit(0, H: 300, texts: ["LONG one", "short", "short"])
        XCTAssertFalse(r.overflow)
        XCTAssertGreaterThan(r.heights[0], r.heights[1])
        XCTAssertEqual(r.heights[1], r.heights[2])
        XCTAssertEqual(r.heights[2], r.heights[3])                      // Add shares like the others
    }

    func testMoreCountFontTracksTheMacRatio() {
        XCTAssertEqual(FutureFit.moreFont(0), 15, accuracy: 0.01)                    // 15 beside 24
        XCTAssertEqual(FutureFit.moreFont(FutureFit.steps - 1), 12.5, accuracy: 0.01) // 15/18 × 15
    }
}
