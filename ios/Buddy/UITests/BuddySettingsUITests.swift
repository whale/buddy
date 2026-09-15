import XCTest

final class BuddySettingsUITests: XCTestCase {
    func testUnavailableLimitExplainsWhyWithoutChangingTasks() {
        for level in 0...2 {
            let app = XCUIApplication()
            app.launchArguments = ["-uiFixture", "settings-limit-6-level-\(level)"]
            app.launch()
            let three = app.buttons["3 active tasks"]
            XCTAssertTrue(three.waitForExistence(timeout: 5))
            XCTAssertEqual(three.value as? String, "Unavailable")
            three.tap()
            XCTAssertTrue(app.staticTexts["Complete or move \(level + 1) task\(level == 0 ? "" : "s") out of Today to choose 3."].exists)
            XCTAssertTrue(app.buttons["6 active tasks"].isSelected)
            XCTAssertFalse(app.alerts.firstMatch.exists)
            XCTAssertFalse(app.staticTexts["Show the morning planner automatically"].exists)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Unavailable task limits level \(level)"
            shot.lifetime = .keepAlways
            add(shot)
            app.buttons["\(4 + level) active tasks"].tap()
            XCTAssertTrue(app.buttons["\(4 + level) active tasks"].isSelected)
            app.terminate()
        }
    }
}
