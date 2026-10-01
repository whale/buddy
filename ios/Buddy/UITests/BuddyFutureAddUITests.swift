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

    // Few items → plain rows + Add share the panel equally (each ≥ 110pt), no empty band.
    func testShortListFillsPanelWithEqualRows() throws {
        let app = launch()
        let r1 = el(app, "future-row-f1"), r2 = el(app, "future-row-f2"), add = el(app, "future-add")
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        let rowH = pitch(r1, r2) - 1
        XCTAssertGreaterThan(rowH, 110, "rows stretch past the 110pt floor to fill")
        XCTAssertEqual(rowH, add.frame.height, accuracy: 1.5, "plain rows and Add get equal shares")
        let barTop = el(app, "chrome-calendar").frame.minY
        XCTAssertGreaterThan(add.frame.maxY, barTop - 60, "Add reaches the panel bottom (no empty band; the icon sits ~40pt into the bottom bar)")
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
        XCTAssertGreaterThanOrEqual(pitch(p1, p2) - 1, 110)
        XCTAssertEqual(pitch(p1, p2) - 1, el(app, "future-add").frame.height, accuracy: 1.5)
    }

    // Overflow → rows sit at the 110pt floor, the list scrolls, Add stays pinned & tappable.
    func testOverflowScrollsWithPinnedAdd() throws {
        let app = launch("future-long")
        let add = el(app, "future-add")
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertEqual(pitch(el(app, "future-row-fl1"), el(app, "future-row-fl2")) - 1, 110, accuracy: 1)
        XCTAssertEqual(add.frame.height, 110, accuracy: 1)
        XCTAssertTrue(add.isHittable)
        XCTAssertFalse(el(app, "future-row-fl12").isHittable, "the end of the list is scrolled off")
    }
}
