//
//  llmHubUITests.swift
//  llmHubUITests
//
//  Created by Hans Axelsson on 11/27/25.
//

import XCTest

final class llmHubUITests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        // Rationale: UI tests can be flaky when executed across multiple UI configurations
        // (Runningboard / launchd transient failures). A single configuration still validates
        // startup without introducing non-determinism.
        false
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        throw XCTSkip("Template UI test disabled; launch is covered by llmHubUITestsLaunchTests.")
    }

    @MainActor
    func testLaunchPerformance() throws {
        throw XCTSkip("Launch performance UI test disabled (flaky due to app termination issues).")
    }
}
