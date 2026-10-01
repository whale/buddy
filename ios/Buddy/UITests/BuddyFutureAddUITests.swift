import XCTest

// History → Future → Add: real taps + typing, like Today's Add row.
final class BuddyFutureAddUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ fixture: String = "history") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiFixture", fixture, "-uiTab", "Future"]
        app.launch()
        return app
    }

    private func draftEditor(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["future-editor-future-draft"].firstMatch
    }

    func testAddTypeReturnCommitsAtBottom() throws {
        let app = launch()
        let add = app.descendants(matching: .any)["future-add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        let editor = draftEditor(app)
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Add should open a draft editor")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "Draft should own the keyboard")
        editor.typeText("Call the")
        sleep(1)
        saveShot("9-keyboard-short-draft")
        editor.typeText(XCUIKeyboardKey.delete.rawValue + String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7))
        editor.typeText("Call the bank\n")
        XCTAssertTrue(app.staticTexts["Call the bank"].waitForExistence(timeout: 3), "Return commits the draft")
        XCTAssertFalse(draftEditor(app).exists, "Return ends the draft (no chained row)")
        // Oldest first → the new row sits below the seeded ones.
        XCTAssertGreaterThan(app.staticTexts["Call the bank"].frame.minY, app.staticTexts["Plan Q3 offsite"].frame.minY)
    }

    /// Evidence capture: set TEST_RUNNER_BUDDY_SHOT_DIR to save keyboard-up PNGs there.
    private func saveShot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["BUDDY_SHOT_DIR"] else { return }
        let name = name + (ProcessInfo.processInfo.environment["BUDDY_SHOT_TAG"] ?? "")
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testLongListDraftStaysAboveKeyboard() throws {
        let app = launch("future-long")
        let add = app.descendants(matching: .any)["future-add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertTrue(add.isHittable, "Add is pinned on screen even with 12 rows")
        add.tap()
        let editor = draftEditor(app)
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        editor.typeText("Call the bank about the mortgage paperwork before Friday and ask about the rate")
        sleep(1)
        XCTAssertLessThanOrEqual(editor.frame.maxY, keyboard.frame.minY + 1, "Draft must stay above the keyboard")
        XCTAssertLessThanOrEqual(editor.frame.maxX, app.windows.firstMatch.frame.maxX, "Long draft wraps, not overflows")
        saveShot("8-keyboard-long-draft")
        editor.typeText("\n")
        XCTAssertTrue(app.staticTexts["Call the bank about the mortgage paperwork before Friday and ask about the rate"].waitForExistence(timeout: 3))
    }

    func testAddTwiceDoesNotGlueOrGhost() throws {
        let app = launch()
        let add = app.descendants(matching: .any)["future-add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        XCTAssertTrue(draftEditor(app).waitForExistence(timeout: 3))
        draftEditor(app).typeText("First")
        add.tap()                                   // commits "First", opens a fresh draft
        XCTAssertTrue(app.staticTexts["First"].waitForExistence(timeout: 3))
        XCTAssertTrue(draftEditor(app).waitForExistence(timeout: 3))
        draftEditor(app).typeText("Second\n")
        XCTAssertTrue(app.staticTexts["Second"].waitForExistence(timeout: 3), "Second entry must stand alone")
        XCTAssertFalse(app.staticTexts["FirstSecond"].exists)
        add.tap(); add.tap()                        // empty drafts are discarded, never committed
        XCTAssertTrue(draftEditor(app).waitForExistence(timeout: 3))
    }

    func testEditExistingRowAndSwitchTabCommits() throws {
        let app = launch()
        let row = app.staticTexts["Renew the domain"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        let editor = app.descendants(matching: .any)["future-editor-f1"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Tapping a Future row edits it")
        editor.typeText(" now\n")
        XCTAssertTrue(app.staticTexts["Renew the domain now"].waitForExistence(timeout: 3))

        // Draft with text + leave the tab → committed.
        app.descendants(matching: .any)["future-add"].firstMatch.tap()
        XCTAssertTrue(draftEditor(app).waitForExistence(timeout: 3))
        draftEditor(app).typeText("Kept on leave")
        app.staticTexts["Done"].firstMatch.tap()
        app.staticTexts["Future"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Kept on leave"].waitForExistence(timeout: 3))
    }

    // END-TO-END background-commit check: a draft typed in Future is still there after
    // background → kill → relaunch. HONEST LIMIT: this does NOT prove the immediate disk
    // write on .background — on the simulator the keyboard's own end-editing commit plus
    // the 0.25s debounced save also land inside iOS's background grace period (verified:
    // it passes with the .background commit removed). The immediate write is pinned by the
    // unit test FutureAddStoreTests.testImmediateAddAndEditReachDiskWithoutDebounce.
    func testBackgroundedDraftIsStillThereAfterRelaunch_EndToEnd() throws {
        let app = launch()
        let add = app.descendants(matching: .any)["future-add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertEqual(add.label, "Add to Future")
        add.tap()
        XCTAssertTrue(draftEditor(app).waitForExistence(timeout: 3))
        draftEditor(app).typeText("Survives the kill")
        XCUIDevice.shared.press(.home)                 // → .background (commit + immediate save)
        // A real kill (swipe away in the app switcher) can only happen once the app is
        // backgrounded — wait for that, then kill without giving a debounced save extra time.
        let backgrounded = NSPredicate { _, _ in
            app.state == .runningBackground || app.state == .runningBackgroundSuspended
        }
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: backgrounded, object: nil)], timeout: 5), .completed)
        app.terminate()

        let relaunched = XCUIApplication()             // no fixture → loads what's on disk
        relaunched.launch()
        let calendar = relaunched.descendants(matching: .any)["chrome-calendar"].firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 5))
        calendar.tap()
        relaunched.staticTexts["Future"].firstMatch.tap()
        XCTAssertTrue(relaunched.staticTexts["Survives the kill"].waitForExistence(timeout: 3),
                      "A backgrounded Future draft must be persisted before the app can be killed")
    }

    // Same title as an existing row (case/whitespace-insensitive) → nothing added; the
    // existing row is flashed instead (sync would otherwise make one of them vanish).
    func testDuplicateTitleIsNotAdded() throws {
        let app = launch()
        let add = app.descendants(matching: .any)["future-add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        XCTAssertTrue(draftEditor(app).waitForExistence(timeout: 3))
        draftEditor(app).typeText("  renew THE   domain\n")
        // The flash lasts ~1.2s — read ONE accessibility snapshot straight away (a polling
        // element query can take longer than the flash itself).
        XCTAssertTrue(app.debugDescription.contains("future-highlight"), "The existing row should flash")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label ==[c] 'renew the domain'")).count, 1)
        XCTAssertFalse(app.staticTexts["renew THE domain"].exists)
    }

    // MARK: - Layout (Today's flex rhythm)

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    // A row's accessibility frame is only its text's bounds, so measure plain rows by PITCH:
    // the distance between two consecutive rows' (vertically centred) text = row height + 1pt divider.
    private func pitch(_ a: XCUIElement, _ b: XCUIElement) -> CGFloat { b.frame.midY - a.frame.midY }

    // Few items → big 24pt rows that share the panel equally (each > 110pt), no empty band.
    // (The Add row's accessibility frame is its label, so all rows are measured by pitch.)
    func testShortListFillsPanelWithEqualRows() throws {
        let app = launch()
        let r1 = el(app, "future-row-f1"), r2 = el(app, "future-row-f2"), add = el(app, "future-add")
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        let rowH = pitch(r1, r2) - 1
        XCTAssertGreaterThan(rowH, 110, "rows stretch past the 110pt floor to fill")
        XCTAssertEqual(pitch(r2, add) - 1, rowH, accuracy: 1.5, "plain rows and Add get equal shares")
        let barTop = el(app, "chrome-calendar").frame.minY
        XCTAssertGreaterThan(add.frame.maxY + rowH / 2, barTop - 60, "Add reaches the panel bottom (no empty band)")
    }

    // Sent rows: on TOP (above plain rows, store order kept) and compact like Donezo rows.
    func testSentRowsAreCompactAndOnTop() throws {
        let app = launch("future-sent")
        let a = app.staticTexts["Email the accountant"], b = app.staticTexts["Book the vet"]
        XCTAssertTrue(a.waitForExistence(timeout: 3))
        let p1 = el(app, "future-row-f1"), p2 = el(app, "future-row-f2")
        XCTAssertLessThan(a.frame.minY, b.frame.minY)                  // store order among sent rows
        XCTAssertLessThan(b.frame.maxY, p1.frame.minY)                 // all sent rows above plain rows
        XCTAssertLessThan(pitch(a, b), 60, "sent rows are compact, not 110pt")
        XCTAssertGreaterThan(pitch(p1, p2) - 1, 90, "plain rows stay big (shrink-to-fit may take a step)")
        XCTAssertEqual(pitch(p2, el(app, "future-add")) - 1, pitch(p1, p2) - 1, accuracy: 1.5)
    }

    // ~7 items → rows SHRINK (below 110pt, smaller text) so everything fits — no scroll, no count.
    func testRowsShrinkBeforeScrolling() throws {
        let app = launch("future-7")
        let add = el(app, "future-add")
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        let rowH = pitch(el(app, "future-row-fn1"), el(app, "future-row-fn2")) - 1
        XCTAssertLessThan(rowH, 110, "shrunk below the big row")
        XCTAssertGreaterThan(rowH, 46, "but not yet at the smallest step")
        XCTAssertLessThan(el(app, "future-row-fn1").frame.height, 27, "text shrank from 24pt")
        XCTAssertTrue(el(app, "future-row-fn7").isHittable, "every row is on screen")
        XCTAssertTrue(add.isHittable)
        let more = el(app, "future-more")
        XCTAssertTrue(!more.exists || !more.isHittable, "nothing hidden → no count")
    }

    // ~16 items → smallest step, scrolls under the pinned Add; the quiet count appears, taps to
    // the bottom WITHOUT starting an add, and fades away there.
    func testOverflowScrollsWithPinnedAddAndQuietCount() throws {
        let app = launch("future-16")
        let add = el(app, "future-add")
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertEqual(pitch(el(app, "future-row-fn1"), el(app, "future-row-fn2")) - 1, 46, accuracy: 3)
        XCTAssertTrue(add.isHittable)
        XCTAssertFalse(el(app, "future-row-fn16").isHittable, "the end of the list is scrolled off")
        let more = el(app, "future-more")
        XCTAssertTrue(more.waitForExistence(timeout: 3))
        XCTAssertTrue(more.isHittable)
        XCTAssertTrue(more.label.hasSuffix("more items below"), more.label)
        let n = Int(more.label.split(separator: " ").first ?? "") ?? 0
        XCTAssertGreaterThan(n, 0)
        XCTAssertLessThan(n, 16)
        more.tap()
        sleep(1)
        XCTAssertFalse(draftEditor(app).exists, "tapping the count must not start an add")
        XCTAssertTrue(el(app, "future-row-fn16").isHittable, "tapping the count scrolls to the bottom")
        let gone = el(app, "future-more")
        XCTAssertTrue(!gone.exists || !gone.isHittable, "at the bottom the count fades away")
        saveShot("final-future-16-bottom")
    }

    // Tab pills read "Future (n)" / "Done (n)" on one line.
    func testTabLabelsCarryCounts() throws {
        let app = launch("future-sent")                                  // 2 plain + 2 sent parked
        let fut = el(app, "tab-future"), done = el(app, "tab-done")
        XCTAssertTrue(fut.waitForExistence(timeout: 3))
        XCTAssertEqual(fut.label, "Future, 2", "sent rows aren't counted")
        XCTAssertTrue(done.label.hasPrefix("Done, "), done.label)
        XCTAssertLessThanOrEqual(fut.frame.height, 39, "one line in the 38pt pill")
    }

    // Done shows the first 30 completions; Load more adds 30 (older days carry the date).
    func testDonePagesThirtyThenLoadMore() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiFixture", "done-many", "-uiTab", "Done"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Today task 1"].waitForExistence(timeout: 3))
        // 6 today + 4 × 6 days = 30 → "Day 6 task 4" is the last on page one.
        let loadMore = el(app, "done-load-more")
        for _ in 0..<12 where !loadMore.isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Day 6 task 4"].exists)
        XCTAssertFalse(app.staticTexts["Day 7 task 1"].exists, "page one stops at 30")
        XCTAssertTrue(loadMore.isHittable)
        saveShot("final-done-load-more")
        loadMore.tap()
        XCTAssertTrue(app.staticTexts["Day 7 task 1"].waitForExistence(timeout: 2), "Load more adds the next page")
        // 60 = 6 today + 13 days × 4 + 2 → page two cuts INSIDE day 14.
        XCTAssertTrue(app.staticTexts["Day 14 task 2"].exists)
        XCTAssertFalse(app.staticTexts["Day 14 task 3"].exists, "…30 more, not everything (cut mid-day)")
        let dated = app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[A-Z][a-z]+day, [A-Z][a-z]{2} [0-9]{1,2}$'"))
        XCTAssertGreaterThan(dated.count, 0, "older days read 'Monday, Sep 22'")
    }

    // Evidence driver for a screen recording (skipped in normal runs): slow, row-sized drags
    // down then up the long list so the count's roll and fade can be inspected frame by frame.
    func testRecordScrollForVideo() throws {
        guard ProcessInfo.processInfo.environment["BUDDY_RECORD"] != nil else {
            throw XCTSkip("set TEST_RUNNER_BUDDY_RECORD=1 to drive the recording")
        }
        let app = launch("future-16")
        XCTAssertTrue(el(app, "future-add").waitForExistence(timeout: 3))
        sleep(2)
        let w = app.windows.firstMatch
        func drag(_ from: CGFloat, _ to: CGFloat) {
            w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
                .press(forDuration: 0.1, thenDragTo: w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
            sleep(1)
        }
        for _ in 0..<4 { drag(0.62, 0.55) }      // ~1 row each, downward through the list
        for _ in 0..<3 { drag(0.50, 0.57) }      // back up → count rises (rolls down)
        drag(0.70, 0.30); sleep(1)               // fling to the bottom → fades out
        drag(0.40, 0.52); sleep(2)               // back up a bit → fades in again
    }

    // MARK: - Review 4 regressions

    // Editing a row in a list that FITS must stay a fitting list: the keyboard rising must not
    // flip Future into overflow (pinned Add + "N more") and hide the edited text under Add.
    func testEditInFittingListStaysInline() throws {
        let app = launch("future-6")
        let row = el(app, "future-row-fn5")
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        let editor = el(app, "future-editor-fn5")
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        editor.typeText(" and then a long tail that wraps onto a second line")
        sleep(1)
        saveShot("fix-1-edit-fitting")
        let more = el(app, "future-more")
        XCTAssertTrue(!more.exists || !more.isHittable, "no 'N more' — nothing is hidden")
        XCTAssertLessThanOrEqual(editor.frame.maxY, keyboard.frame.minY + 1, "edited text above the keyboard")
        let add = el(app, "future-add")
        XCTAssertTrue(!add.isHittable || add.frame.minY >= editor.frame.maxY - 1, "Add never covers the edited text")
    }

    // The quiet count must re-count when the keyboard shortens the list (not stay stale).
    func testCountUpdatesWhenKeyboardRises() throws {
        let app = launch("future-12")
        let row = el(app, "future-row-fn2")
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        let editor = el(app, "future-editor-fn2")
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText(" soon")                       // the simulator raises its keyboard on typing
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        // Wait until the keyboard is really up on screen (not just in the tree).
        let up = NSPredicate { _, _ in keyboard.exists && keyboard.frame.minY < app.windows.firstMatch.frame.maxY - 200 }
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: up, object: nil)], timeout: 5), .completed)
        sleep(1)
        saveShot("fix-2-count-keyboard")
        let add = el(app, "future-add"), more = el(app, "future-more")
        XCTAssertTrue(more.waitForExistence(timeout: 2))
        let n = Int(more.label.split(separator: " ").first ?? "") ?? -1
        let pitchH = pitch(el(app, "future-row-fn3"), el(app, "future-row-fn4"))
        let addTop = add.frame.midY - pitchH / 2
        let hidden = (1...12).filter { i in
            let r = el(app, "future-row-fn\(i)")
            return r.exists && r.frame.midY > addTop
        }.count
        XCTAssertEqual(n, hidden, accuracy: 1, "count \(n) vs rows actually under Add \(hidden)")
    }

    // Committing a draft in an overflowing list leaves the new row in view, just above Add.
    func testCommitDraftInOverflowKeepsNewRowAboveAdd() throws {
        let app = launch("future-12")
        let add = el(app, "future-add")
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        XCTAssertTrue(draftEditor(app).waitForExistence(timeout: 3))
        draftEditor(app).typeText("Brand new thing\n")
        sleep(1)
        saveShot("fix-3-commit-overflow")
        let fresh = app.staticTexts["Brand new thing"]
        XCTAssertTrue(fresh.waitForExistence(timeout: 2))
        XCTAssertTrue(fresh.isHittable, "the new row is in view")
        XCTAssertLessThanOrEqual(fresh.frame.maxY, el(app, "future-add").frame.minY, "…and not under the pinned Add")
        XCTAssertFalse(el(app, "future-row-fn1").isHittable, "the list didn't jump back to the top")
    }
}
