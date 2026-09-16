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
            XCTAssertTrue(app.staticTexts["Your list needs room"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts["You have \(4 + level) active tasks. To lower your limit to 3, first complete \(level + 1) task\(level == 0 ? "" : "s") or move \(level == 0 ? "it" : "them") to Future."].exists)
            XCTAssertEqual(app.buttons.matching(identifier: "taskLimitOK").count, 1)
            XCTAssertFalse(app.buttons["Cancel"].exists)
            XCTAssertTrue(app.alerts.firstMatch.exists)
            XCTAssertFalse(app.staticTexts["Show the morning planner automatically"].exists)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Unavailable task limits level \(level)"
            shot.lifetime = .keepAlways
            add(shot)
            app.buttons["taskLimitOK"].tap()
            XCTAssertFalse(app.staticTexts["Your list needs room"].exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Complete or move")).firstMatch.exists)
            let settingsShot = XCTAttachment(screenshot: app.screenshot())
            settingsShot.name = "Settings without duplicate explanation level \(level)"
            settingsShot.lifetime = .keepAlways
            add(settingsShot)
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
        XCTAssertFalse(app.staticTexts["Your list needs room"].exists)
    }

}
