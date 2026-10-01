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

    // Review #1: a draft typed in Future survives background → kill → relaunch.
    func testDraftSurvivesBackgroundThenKill() throws {
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
}
