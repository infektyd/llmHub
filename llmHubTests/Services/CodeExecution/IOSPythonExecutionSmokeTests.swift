import XCTest
@testable import llmHub

final class IOSPythonExecutionSmokeTests: XCTestCase {

    func testPythonBridgeReturnsUnavailableWhenNotEmbeddedInMacOSTests() async throws {
        #if os(macOS)
        // On macOS unit tests, the embedded iOS Python.framework isn't present.
        // The important property: we fail closed (report interpreter unavailable)
        // and do not crash the host.
        let backend = IOSLocalExecutionBackend()
        let info = await backend.checkInterpreter(for: .python)
        XCTAssertFalse(info.isAvailable)
        #endif
    }
}
