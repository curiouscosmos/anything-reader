//
//  Anything_ReaderUITestsLaunchTests.swift
//  Anything ReaderUITests
//
//  Created by Daman Mehta on 2026-04-24.
//

import XCTest

final class Anything_ReaderUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Listen to anything"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["topbar-settings-button"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
