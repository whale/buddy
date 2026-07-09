import XCTest
@testable import Buddy

final class RowFitTests: XCTestCase {
    func testTightDonezoListShrinksAddRowInsteadOfKeepingFullSize() {
        let fit = RowFit.compute(active: [], done: Array(repeating: "Finished item", count: 5),
                                 height: 190, width: 400,
                                 includesAdd: true)
        XCTAssertLessThan(fit.font, 24)
        XCTAssertEqual(fit.vpad, RowFit.padMin)
    }

    func testHardCapDoesNotReserveMissingAddRow() {
        let withAdd = RowFit.compute(active: Array(repeating: "Task", count: 6), done: [],
                                     height: 260, width: 400,
                                     includesAdd: true)
        let withoutAdd = RowFit.compute(active: Array(repeating: "Task", count: 6), done: [],
                                        height: 260, width: 400,
                                        includesAdd: false)
        XCTAssertGreaterThanOrEqual(withoutAdd.font, withAdd.font)
    }
}
