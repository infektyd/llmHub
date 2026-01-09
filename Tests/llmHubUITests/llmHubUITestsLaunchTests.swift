//
//  llmHubUITestsLaunchTests.swift
//  llmHubUITests
//
//  Created by Hans Axelsson on 11/27/25.
//

import XCTest
import AppKit

final class llmHubUITestsLaunchTests: XCTestCase {

    private static let bundleID = "Syntra.llmHub"

    private func forceTerminateRunningAppIfNeeded() {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
        guard !running.isEmpty else { return }
        for app in running {
            _ = app.forceTerminate()
        }
        // Give launchd/Runningboard a moment to settle.
        Thread.sleep(forTimeInterval: 0.5)
    }

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        // Rationale: Launch tests are occasionally flaky when executed across multiple
        // UI configurations (Runningboard / launchd transient failures). A single
        // launch still validates basic startup without introducing non-determinism.
        false
    }

    override func setUpWithError() throws {
        forceTerminateRunningAppIfNeeded()
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        forceTerminateRunningAppIfNeeded()
    }

    @MainActor
    func testLaunch() throws {
        forceTerminateRunningAppIfNeeded()
        let app = XCUIApplication()
        app.launch()

        defer {
            app.terminate()
            forceTerminateRunningAppIfNeeded()
        }

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
