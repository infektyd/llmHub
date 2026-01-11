import XCTest
@testable import llmHub

final class IOSPythonExecutionSmokeTests: XCTestCase {

    func testPythonBridgeReturnsUnavailableWhenNotEmbeddedInMacOSTests() async throws {
        #if os(macOS)
        // On macOS unit tests, the embedded iOS Python.framework isn't present.
        // The important property: we fail closed (report interpreter unavailable)
        // and do not crash the host.
        let backend = iOSPythonExecutionBackend()
        let info = await backend.checkInterpreter(for: .python)
        XCTAssertFalse(info.isAvailable)
        #endif
    }

    #if os(iOS)
    private func requireBackendAvailable(_ backend: iOSPythonExecutionBackend) async throws {
        guard await backend.isAvailable else {
            throw XCTSkip("Embedded Python framework is not available.")
        }
    }

    func testPythonExecutionPrintsStdout() async throws {
        let backend = iOSPythonExecutionBackend()
        try await requireBackendAvailable(backend)

        let result = try await backend.execute(
            code: "print('hello')",
            language: .python,
            timeout: 10,
            workingDirectory: nil
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
        XCTAssertTrue(result.stderr.isEmpty)
    }

    func testPythonExecutionImportsNumpy() async throws {
        let backend = iOSPythonExecutionBackend()
        try await requireBackendAvailable(backend)

        let code = """
        import numpy as np
        print(np.array([1, 2, 3]).sum())
        """

        let result = try await backend.execute(
            code: code,
            language: .python,
            timeout: 10,
            workingDirectory: nil
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "6")
    }

    func testPythonExecutionImportsMatplotlib() async throws {
        let backend = iOSPythonExecutionBackend()
        try await requireBackendAvailable(backend)

        let code = """
        import matplotlib
        print("matplotlib-ok")
        """

        let result = try await backend.execute(
            code: code,
            language: .python,
            timeout: 10,
            workingDirectory: nil
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "matplotlib-ok")
    }

    func testPythonExecutionTimeout() async throws {
        let backend = iOSPythonExecutionBackend()
        try await requireBackendAvailable(backend)

        let code = """
        import time
        time.sleep(6)
        """

        do {
            _ = try await backend.execute(
                code: code,
                language: .python,
                timeout: 5,
                workingDirectory: nil
            )
            XCTFail("Expected execution to time out.")
        } catch let error as CodeExecutionError {
            if case .timeout = error {
                return
            }
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPythonExecutionRepeatedRuns() async throws {
        let backend = iOSPythonExecutionBackend()
        try await requireBackendAvailable(backend)

        for _ in 0..<100 {
            let result = try await backend.execute(
                code: "print('ok')",
                language: .python,
                timeout: 10,
                workingDirectory: nil
            )
            XCTAssertEqual(result.exitCode, 0)
        }
    }
    #endif
}
