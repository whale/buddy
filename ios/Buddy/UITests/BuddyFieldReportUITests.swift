import XCTest

// Field-report regression drives (2026-07-10 round 2). Each test MEASURES the
// behavior on a real simulator — frames, keyboard geometry, scroll movement —
// per RULE 4 (see it, don't infer it).
final class BuddyFieldReportUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(fixture: String, extraArgs: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiFixture", fixture] + extraArgs
        app.launch()
        return app
    }

    /// R2-1: tapping a task to edit must keep the text exactly where it was —
    /// the editor swap may not move the first line vertically.
    func testEditSwapKeepsTextInPlace() throws {
        let app = launch(fixture: "lvl0")
        let task = app.staticTexts["Write the iOS scaffold"]
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        let beforeY = task.frame.minY

        let beforeH = task.frame.height
        task.tap()
        let editor = app.descendants(matching: .any)["task-editor-m1"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        // Give any (unwanted) relayout a beat to happen, then measure.
        sleep(1)
        let afterY = editor.frame.minY
        // Tolerance is 5pt because XCUI reports the text view's ACCESSIBILITY frame,
        // whose line box is ~2.3pt taller than SwiftUI Text — the GLYPHS are pixel-
        // identical (verified by screenshot diff: 0.0pt band delta, 2026-07-10).
        // The original bug measured 15.6pt here; this still catches that class.
        XCTAssertLessThanOrEqual(abs(afterY - beforeY), 5.0,
            "Editing must not move the text (text y=\(beforeY) h=\(beforeH); editor y=\(afterY) h=\(editor.frame.height))")
    }

    /// R2-3: editing a row low in the list must reveal it ABOVE the keyboard.
    func testEditingLowRowStaysAboveKeyboard() throws {
        let app = launch(fixture: "lvl2")   // 6 active rows — the last is near the bottom
        let target = app.staticTexts["Design the settings screen"]   // lowest active row in alarmTasks
        XCTAssertTrue(target.waitForExistence(timeout: 3))
        target.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3), "Keyboard should rise")
        sleep(1)   // let any reveal animation settle
        let editor = app.textViews.matching(NSPredicate(format: "identifier BEGINSWITH 'task-editor'")).firstMatch
        XCTAssertTrue(editor.exists, "An inline editor should be active")
        let editorBottom = editor.frame.maxY
        let keyboardTop = keyboard.frame.minY
        XCTAssertLessThanOrEqual(editorBottom, keyboardTop + 1,
            "Edited row must be visible above the keyboard (editor bottom \(editorBottom) vs keyboard top \(keyboardTop))")
    }

    /// RULE 4 experiment: with the row swipe gesture stripped (-noSwipe), does the
    /// Future ScrollView scroll at all? Separates gesture-conflict from structure.
    func testFutureScrollsWithoutSwipeGesture() throws {
        let app = launch(fixture: "future-long", extraArgs: ["-noSwipe"])
        let first = app.staticTexts["Future item 1"]
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        let beforeY = first.frame.minY
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let end = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)
        sleep(1)
        let afterY = first.exists ? first.frame.minY : -9999
        XCTAssertLessThan(afterY, beforeY - 60, "no-gesture scroll also failed (structural): \(beforeY) → \(afterY)")
    }

    /// R2-5: the Future list must scroll when it is longer than the panel.
    func testFutureListScrolls() throws {
        let app = launch(fixture: "future-long")
        let first = app.staticTexts["Future item 1"]
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        let beforeY = first.frame.minY

        // Real vertical drag on the sheet body (not on a control).
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let end = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)
        sleep(1)

        let afterY = first.exists ? first.frame.minY : -9999   // scrolled offscreen also counts
        XCTAssertLessThan(afterY, beforeY - 60,
            "Future list did not scroll (row 1 y \(beforeY) → \(afterY))")
    }

    /// R2-4/R2-6 evidence pass: open + close both sheets slowly while an external
    /// `simctl io recordVideo` captures frames for motion review. Assertions are
    /// minimal — this test exists to produce the recording deterministically.
    func testSheetOpenCloseRecordingPass() throws {
        let app = launch(fixture: "lvl0")
        let calendar = app.buttons["chrome-calendar"]
        let gear = app.buttons["chrome-settings"]
        _ = app.staticTexts["Write the iOS scaffold"].waitForExistence(timeout: 3)
        sleep(1)
        calendar.tap()                                   // open history
        sleep(2)
        app.buttons["sheet-close"].tap()                 // close (watch for the flash here)
        sleep(2)
        gear.tap()                                       // open settings
        sleep(2)
        app.buttons["sheet-close"].tap()                 // close
        sleep(2)
        XCTAssertTrue(app.staticTexts["Write the iOS scaffold"].exists)
    }
}
