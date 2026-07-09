import XCTest

final class BuddyEditingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTapTaskEntersEditingKeepsKeyboardFocused() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiFixture", "lvl0"]
        app.launch()

        let original = "Write the iOS scaffold"
        let task = app.staticTexts[original]
        XCTAssertTrue(task.waitForExistence(timeout: 3), "Expected seeded task row to be visible")

        task.tap()

        let editor = app.descendants(matching: .any)["task-editor-m1"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Tapping the row should swap it into the inline editor")

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3), "Tapping the row should raise the software keyboard")

        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        XCTAssertTrue(focused.evaluate(with: editor), "The inline editor should own keyboard focus")

        sleep(1)
        XCTAssertTrue(editor.exists, "The editor should not flicker back into static text after focus settles")
        XCTAssertTrue(keyboard.exists, "The software keyboard should remain visible after focus settles")
        XCTAssertTrue(focused.evaluate(with: editor), "The inline editor should keep keyboard focus after focus settles")
    }
}
