//
//  Anything_ReaderUITests.swift
//  Anything ReaderUITests
//

import XCTest

final class Anything_ReaderUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeScreenShowsCoreControls() throws {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["Listen to anything"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["topbar-home-button"].exists)
        XCTAssertTrue(app.buttons["topbar-paste-text-button"].exists)
        XCTAssertTrue(app.buttons["topbar-upload-button"].exists)
        XCTAssertTrue(app.buttons["topbar-settings-button"].exists)
        XCTAssertTrue(app.textFields["Search books, text, categories"].exists)
        XCTAssertTrue(app.buttons["hero-download-tts-button"].exists)
    }

    @MainActor
    func testSettingsSheetOpensAndCloses() throws {
        let app = launchApp()

        app.buttons["topbar-settings-button"].tap()

        XCTAssertTrue(app.buttons["settings-sheet-done-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Appearance"].exists)
        XCTAssertTrue(app.staticTexts["Kokoro Voice"].exists)

        app.buttons["settings-sheet-done-button"].tap()

        XCTAssertFalse(app.buttons["settings-sheet-done-button"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testPasteSheetOpensAndCancels() throws {
        let app = launchApp()

        app.buttons["topbar-paste-text-button"].tap()

        XCTAssertTrue(app.buttons["paste-text-sheet-play-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Paste text to listen"].exists)
        XCTAssertTrue(app.buttons["paste-text-sheet-cancel-button"].exists)

        app.buttons["paste-text-sheet-cancel-button"].tap()

        XCTAssertFalse(app.buttons["paste-text-sheet-play-button"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            _ = launchApp()
        }
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }
}
