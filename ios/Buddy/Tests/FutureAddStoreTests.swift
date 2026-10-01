import XCTest
@testable import Buddy

// History → Future: add / edit straight into the parked list.
final class FutureAddStoreTests: XCTestCase {
    private func store(_ deferred: [DeferredTask] = []) -> BuddyStore {
        let s = BuddyStore()
        s.seedForScreenshot(tasks: [])
        s.deferred = deferred
        return s
    }

    func testAddDeferredAppendsTrimmedRowAtBottom() {
        let s = store([DeferredTask(id: "old", text: "Old", wake: "")])
        let id = s.addDeferred(text: "  Renew the domain \n")
        XCTAssertNotNil(id)
        XCTAssertEqual(s.deferred.count, 2)
        XCTAssertEqual(s.deferred.last?.id, id)                 // oldest first → new row last
        XCTAssertEqual(s.deferred.last?.text, "Renew the domain")
        XCTAssertEqual(s.deferred.last?.v, 1)
        XCTAssertEqual(s.deferred.last?.wake, "")
        XCTAssertNil(s.deferred.last?.sent)
        XCTAssertEqual(id, id?.uppercased())                     // iPhone mints UPPERCASE ids
    }

    func testAddDeferredRejectsBlankAndWhitespace() {
        let s = store()
        XCTAssertNil(s.addDeferred(text: ""))
        XCTAssertNil(s.addDeferred(text: "   \n\t "))
        XCTAssertTrue(s.deferred.isEmpty)                        // a blank row never reaches the synced list
    }

    func testEditDeferredBumpsVersion() {
        let s = store([DeferredTask(id: "a", text: "Before", wake: "", v: 3)])
        s.editDeferred(id: "a", text: " After ")
        XCTAssertEqual(s.deferred[0].text, "After")
        XCTAssertEqual(s.deferred[0].v, 4)
    }

    func testEditDeferredUnchangedTextDoesNotBump() {
        let s = store([DeferredTask(id: "a", text: "Same", wake: "", v: 2)])
        s.editDeferred(id: "a", text: "Same  ")
        XCTAssertEqual(s.deferred[0].v, 2)
    }

    func testEditDeferredToEmptyDeletesAndTombstones() {
        let s = store([DeferredTask(id: "a", text: "Gone", wake: ""), DeferredTask(id: "b", text: "Stay", wake: "")])
        s.editDeferred(id: "a", text: "   ")
        XCTAssertEqual(s.deferred.map(\.id), ["b"])
        XCTAssertNotNil(s.tombstones["a"])                      // same path as × — can't resurrect via sync
    }

    func testEditDeferredIgnoresSentRows() {
        let s = store([DeferredTask(id: "a", text: "Sent", wake: "", sent: true, sentTid: "t", v: 2)])
        s.editDeferred(id: "a", text: "Changed")
        XCTAssertEqual(s.deferred[0].text, "Sent")
        XCTAssertEqual(s.deferred[0].v, 2)
    }

    // Review #2: an UNCHANGED edit must not revert a value a sync adopted mid-edit.
    func testUnchangedEditIsNoOpEvenIfSyncChangedRowMidEdit() {
        let s = store([DeferredTask(id: "a", text: "Old title", wake: "", v: 2)])
        let original = s.deferred[0].text              // user taps the row → editor holds "Old title"
        s.deferred[0].text = "Newer from Mac"          // a sync adopt lands mid-edit
        s.deferred[0].v = 3
        s.editDeferred(id: "a", text: "Old title ", original: original)   // Return with no change
        XCTAssertEqual(s.deferred[0].text, "Newer from Mac")
        XCTAssertEqual(s.deferred[0].v, 3)
    }

    func testChangedEditWithOriginalStillApplies() {
        let s = store([DeferredTask(id: "a", text: "Old", wake: "", v: 2)])
        s.editDeferred(id: "a", text: "New", original: "Old")
        XCTAssertEqual(s.deferred[0].text, "New")
        XCTAssertEqual(s.deferred[0].v, 3)
        s.editDeferred(id: "a", text: "  ", original: "New")   // cleared → still deletes
        XCTAssertTrue(s.deferred.isEmpty)
        XCTAssertNotNil(s.tombstones["a"])
    }

    // Review #1: the backgrounding path writes to disk NOW (the app may be killed next).
    func testImmediateAddAndEditReachDiskWithoutDebounce() {
        let s = store()
        let id = s.addDeferred(text: "Survives a kill", immediate: true)!
        XCTAssertEqual(BuddyStore().deferred.first(where: { $0.id == id })?.text, "Survives a kill")
        s.editDeferred(id: id, text: "Edited before kill", original: "Survives a kill", immediate: true)
        XCTAssertEqual(BuddyStore().deferred.first(where: { $0.id == id })?.text, "Edited before kill")
    }
}
