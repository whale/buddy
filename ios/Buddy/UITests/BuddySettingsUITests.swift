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
            XCTAssertTrue(app.staticTexts["Make room for a smaller list"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts["You have \(4 + level) active tasks. Move \(level + 1) to Future, or complete \(level == 0 ? "it" : "them"), before choosing a limit of 3."].exists)
            XCTAssertEqual(app.buttons.matching(identifier: "taskLimitOK").count, 1)
            XCTAssertFalse(app.buttons["Cancel"].exists)
            XCTAssertTrue(app.alerts.firstMatch.exists)
            XCTAssertFalse(app.staticTexts["Show the morning planner automatically"].exists)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Unavailable task limits level \(level)"
            shot.lifetime = .keepAlways
            add(shot)
            app.buttons["taskLimitOK"].tap()
            XCTAssertFalse(app.staticTexts["Make room for a smaller list"].exists)
            XCTAssertTrue(app.buttons["6 active tasks"].isSelected)
            app.buttons["\(4 + level) active tasks"].tap()
            XCTAssertTrue(app.buttons["\(4 + level) active tasks"].isSelected)
            app.terminate()
        }
    }
    func testLimitExplanationAtLargestTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiFixture", "settings-limit-6-level-1", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let three = app.buttons["3 active tasks"]
        XCTAssertTrue(three.waitForExistence(timeout: 5))
        three.tap()
        let ok = app.buttons["taskLimitOK"]
        XCTAssertTrue(ok.waitForExistence(timeout: 3))
        XCTAssertTrue(ok.isHittable)
        XCTAssertLessThanOrEqual(ok.frame.maxY, app.frame.maxY - 24)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Limit explanation largest text"
        shot.lifetime = .keepAlways
        add(shot)
        ok.tap()
        XCTAssertFalse(app.staticTexts["Make room for a smaller list"].exists)
    }

}
