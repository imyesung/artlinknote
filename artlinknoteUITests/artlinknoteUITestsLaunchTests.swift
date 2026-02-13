//
//  artlinknoteUITestsLaunchTests.swift
//  artlinknoteUITests
//

import XCTest

final class artlinknoteUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-disable-animations"]
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable" // quieter logs
        app.launch()

        // Sanity check: first screen should have the navigation title "Artlink"
        // (ContentView.navigationTitle("Artlink"))
        let navBar = app.navigationBars["Artlink"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 5), "App did not reach initial screen in time")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
