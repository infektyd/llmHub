import XCTest
@testable import llmHub

final class MacOSCodeExecutionSmokeTests: XCTestCase {
    func testSwiftExecutionViaXPC() async throws {
        #if os(macOS)
        let engine = await MainActor.run { CodeExecutionEngine() }
        guard await engine.isBackendAvailable else {
            throw XCTSkip("XPC code execution backend is not available.")
        }

        let interpreter = await engine.findInterpreter(for: .swift)
        guard interpreter.isAvailable else {
            throw XCTSkip("Swift interpreter is not available on this system.")
        }

        let result = try await engine.execute(
            request: CodeExecutionRequest(
                language: .swift,
                code: "print(\"ok\")",
                timeoutSeconds: 10
            ),
            securityMode: .sandbox
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "ok")
        #else
        throw XCTSkip("macOS-only test.")
        #endif
    }
}
