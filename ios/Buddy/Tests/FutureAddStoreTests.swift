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
        guard case .added(let id)? = s.addDeferred(text: "  Renew the domain \n") else { return XCTFail("not added") }
        XCTAssertEqual(s.deferred.count, 2)
        XCTAssertEqual(s.deferred.last?.id, id)                 // oldest first → new row last
        XCTAssertEqual(s.deferred.last?.text, "Renew the domain")
        XCTAssertEqual(s.deferred.last?.v, 1)
        XCTAssertEqual(s.deferred.last?.wake, "")
        XCTAssertNil(s.deferred.last?.sent)
        XCTAssertEqual(id, id.uppercased())                      // iPhone mints UPPERCASE ids
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
        guard case .added(let id)? = s.addDeferred(text: "Survives a kill", immediate: true) else { return XCTFail("not added") }
        XCTAssertEqual(BuddyStore().deferred.first(where: { $0.id == id })?.text, "Survives a kill")
        s.editDeferred(id: id, text: "Edited before kill", original: "Survives a kill", immediate: true)
        XCTAssertEqual(BuddyStore().deferred.first(where: { $0.id == id })?.text, "Edited before kill")
    }

    // MARK: - Whitespace (Mac parity: text.replace(/\s+/g,' ').trim())

    func testAddCollapsesInternalWhitespaceAndNewlines() {
        let s = store()
        s.addDeferred(text: "  Call\n\nthe   bank\t now ")
        XCTAssertEqual(s.deferred.last?.text, "Call the bank now")
    }

    func testEditCollapsesInternalWhitespace() {
        let s = store([DeferredTask(id: "a", text: "Old", wake: "")])
        s.editDeferred(id: "a", text: "New\n  pasted   text")
        XCTAssertEqual(s.deferred[0].text, "New pasted text")
    }

    // MARK: - Same-title dedupe (what the sync merge would do, done locally)

    func testAddDuplicateTitleIsNotAddedAndPointsAtExisting() {
        let s = store([DeferredTask(id: "mom", text: "Call mom", wake: "", v: 4)])
        let result = s.addDeferred(text: "  call   MOM ")
        XCTAssertEqual(result, .duplicate("mom"))
        XCTAssertEqual(s.deferred.map(\.id), ["mom"])           // the user's existing row survives untouched
        XCTAssertEqual(s.deferred[0].v, 4)
    }

    func testAddMatchingOnlyASentRowStillAdds() {
        let s = store([DeferredTask(id: "sent", text: "Call mom", wake: "", sent: true, sentTid: "t")])
        guard case .added = s.addDeferred(text: "Call mom") else { return XCTFail("sent rows don't dedupe") }
        XCTAssertEqual(s.deferred.count, 2)
    }

    func testEditOntoAnotherTitleKeepsEditedRowAndDeletesOther() {
        let s = store([DeferredTask(id: "a", text: "Call mom", wake: "", v: 5),
                       DeferredTask(id: "b", text: "Ring someone", wake: "", v: 1)])
        s.editDeferred(id: "b", text: "  call   MOM ", original: "Ring someone")
        XCTAssertEqual(s.deferred.map(\.id), ["b"])              // edited row kept…
        XCTAssertEqual(s.deferred[0].text, "call MOM")
        XCTAssertEqual(s.deferred[0].v, 2)                       // …with the v bump
        XCTAssertNotNil(s.tombstones["a"])                       // other one deleted via the tombstoning path
    }

    func testEditOntoSentRowTitleDoesNotDeleteSentRow() {
        let s = store([DeferredTask(id: "a", text: "Call mom", wake: "", sent: true, sentTid: "t"),
                       DeferredTask(id: "b", text: "Other", wake: "")])
        s.editDeferred(id: "b", text: "Call mom")
        XCTAssertEqual(Set(s.deferred.map(\.id)), ["a", "b"])
    }

    // The result must equal what sync would converge to: merging the deduped state is a no-op.
    func testLocalDedupeMatchesMergeOutcome() {
        let s = store([DeferredTask(id: "a", text: "Call mom", wake: "")])
        s.addDeferred(text: "call MOM")
        let mergedKeys = s.deferred.filter { $0.sent != true }.map { BuddyStore.futureTitleKey($0.text) }
        XCTAssertEqual(mergedKeys.count, Set(mergedKeys).count)  // no two plain rows share a merge key
    }

    // MARK: - Sync guard during a Future edit

    private func snapshot(deferred: [DeferredTask], from s: BuddyStore) -> SyncSnapshot {
        var snap = s.snapshot()
        snap.deferred = deferred
        return snap
    }

    func testAdoptAndRolloverDeferWhileEditingFutureThenApply() {
        let s = store([DeferredTask(id: "a", text: "Local", wake: "")])
        let remote = snapshot(deferred: [DeferredTask(id: "a", text: "From Mac", wake: "", v: 2)], from: s)
        s.isEditingFuture = true
        s.adopt(remote)
        XCTAssertEqual(s.deferred[0].text, "Local")             // not clobbered mid-edit
        XCTAssertFalse(s.performRolloverIfNeeded())             // no rollover mid-edit
        XCTAssertFalse(s.isEditing)                             // independent of Today's flag
        s.isEditingFuture = false                               // edit ends…
        s.adopt(remote)                                         // …the next poll's adopt lands
        XCTAssertEqual(s.deferred[0].text, "From Mac")
    }
}
