//
//  artlinknoteUITests.swift
//  artlinknoteUITests
//

import XCTest

final class artlinknoteUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-disable-animations"]
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launch()

        // Basic sanity check
        XCTAssertTrue(app.navigationBars["Artlink"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments += ["-ui-testing"]
            app.launch()
        }
    }
}
