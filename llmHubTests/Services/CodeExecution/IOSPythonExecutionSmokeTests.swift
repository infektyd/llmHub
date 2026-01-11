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

    func testPythonBackendIsAvailable() throws {
        let env = ToolEnvironment.current
        if !env.hasCodeExecutionBackend {
            throw XCTSkip("Embedded Python framework is not available.")
        }
        XCTAssertTrue(env.hasCodeExecutionBackend)
    }

    func testSimplePrintExecution() async throws {
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

    func testNumpyImport() async throws {
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

    func testPythonExecutionImportsPandas() async throws {
        let backend = iOSPythonExecutionBackend()
        try await requireBackendAvailable(backend)

        let code = """
        import pandas as pd
        df = pd.DataFrame({'a': [1, 2, 3]})
        print(df['a'].sum())
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

    func testPythonExecutionReportsSyntaxError() async throws {
        let backend = iOSPythonExecutionBackend()
        try await requireBackendAvailable(backend)

        let code = """
        def broken(:
            pass
        """

        let result = try await backend.execute(
            code: code,
            language: .python,
            timeout: 10,
            workingDirectory: nil
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("SyntaxError"),
            "Expected SyntaxError in stderr, got: \(result.stderr)"
        )
    }

    func testPythonExecutionReportsRuntimeException() async throws {
        let backend = iOSPythonExecutionBackend()
        try await requireBackendAvailable(backend)

        let code = """
        raise ValueError('boom')
        """

        let result = try await backend.execute(
            code: code,
            language: .python,
            timeout: 10,
            workingDirectory: nil
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("ValueError") || result.stderr.contains("boom"),
            "Expected ValueError trace in stderr, got: \(result.stderr)"
        )
    }

    func testExecutionTimeout() async throws {
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

    // MARK: - Security Mode Tests

    func testSandboxModeRestrictsFileAccess() async throws {
        let backend = iOSPythonExecutionBackend()
        try await requireBackendAvailable(backend)

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        let code = """
        import os
        with open('/tmp/evil.txt', 'w') as f:
            f.write('This should fail!')
        """

        let result = try await backend.execute(
            code: code,
            language: .python,
            timeout: 5,
            workingDirectory: documentsDir
        )

        XCTAssertNotEqual(result.exitCode, 0, "Should fail with PermissionError")
        XCTAssertTrue(
            result.stderr.contains("PermissionError") || result.stderr.contains("Access denied"),
            "Should report permission error in stderr"
        )
    }

    func testUnrestrictedModeAllowsFullAccess() async throws {
        let backend = iOSPythonExecutionBackend()
        try await requireBackendAvailable(backend)

        let code = """
        import tempfile
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            f.write('Unrestricted access works!')
            print(f"Created: {f.name}")
        """

        let result = try await backend.execute(
            code: code,
            language: .python,
            timeout: 5,
            workingDirectory: nil
        )

        XCTAssertEqual(result.exitCode, 0, "Should succeed in unrestricted mode")
        XCTAssertTrue(result.stdout.contains("Created:"))
    }
    #endif
}
