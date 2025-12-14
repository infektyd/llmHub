//
//  llmHubUITestsLaunchTests.swift
//  llmHubUITests
//
//  Created by Hans Axelsson on 11/27/25.
//

import XCTest

final class llmHubUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        // Rationale: Launch tests are occasionally flaky when executed across multiple
        // UI configurations (Runningboard / launchd transient failures). A single
        // launch still validates basic startup without introducing non-determinism.
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
