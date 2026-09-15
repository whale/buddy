import XCTest

final class BuddySettingsUITests: XCTestCase {
    func testReductionRequiresConfirmationAndMorningRemainsMacOnly() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiFixture", "settings-limit-6-level-2"]
        app.launch()
        let three = app.buttons["3 active tasks"]
        XCTAssertTrue(three.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Show the morning planner automatically"].exists)
        three.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["6 active tasks"].isSelected)
        three.tap()
        app.alerts.buttons["Move to Future"].tap()
        XCTAssertTrue(three.isSelected)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Settings at limit 3 after confirmed reduction"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
