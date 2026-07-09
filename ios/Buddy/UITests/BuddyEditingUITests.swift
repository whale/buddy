import XCTest

final class BuddyEditingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTapTaskEntersEditingAndCommitsWithKeyboardDone() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiFixture", "lvl0"]
        app.launch()

        let original = "Write the iOS scaffold"
        let edited = "Write the iOS scaffold updated"
        let task = app.staticTexts[original]
        XCTAssertTrue(task.waitForExistence(timeout: 3), "Expected seeded task row to be visible")

        task.tap()

        let doneButton = app.toolbars.buttons["Done"].firstMatch
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3), "Tapping the row should keep it in edit mode and show the keyboard Done button")

        app.typeText(" updated")
        doneButton.tap()

        XCTAssertTrue(app.staticTexts[edited].waitForExistence(timeout: 3), "Edited task should commit and remain visible")
    }
}
