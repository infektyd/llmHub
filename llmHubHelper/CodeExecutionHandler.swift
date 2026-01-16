//
//  CodeExecutionHandler.swift
//  llmHubHelper
//
//  Implements the XPC protocol for code execution
//  This runs in the helper XPC service and inherits the parent app's App Sandbox
//

#if os(macOS)
import Foundation
import OSLog

/// Handler that implements the XPC protocol for code execution.
/// Runs in the helper XPC process.
final class CodeExecutionHandler: NSObject, CodeExecutionXPCProtocol {

    private let logger = Logger(subsystem: "Syntra.llmHub.CodeExecutionHelper", category: "Handler")
    private let executor = CodeExecutor()

    // MARK: - CodeExecutionXPCProtocol

    /// Executes code in the specified language.
    /// - Parameters:
    ///   - code: The source code to execute.
    ///   - language: The language identifier.
    ///   - timeout: The timeout in seconds.
    ///   - workingDirectory: The working directory path.
    ///   - reply: The completion handler with result data or error.
    func executeCode(
        _ code: String,
        language: String,
        timeout: Int,
        workingDirectory: String?,
        reply: @escaping (Data?, Error?) -> Void
    ) {
        logger.info("Executing \(language) code (\(code.count) chars)")

        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultError: Error?

        Task {
            defer { semaphore.signal() }
            do {
                let result = try await executor.execute(
                    code: code,
                    language: language,
                    timeout: timeout,
                    workingDirectory: workingDirectory
                )

                let encoder = JSONEncoder()
                resultData = try encoder.encode(result)
                logger.info("Execution completed: exit=\(result.exitCode), time=\(result.executionTimeMs)ms")
            } catch {
                logger.error("Execution failed: \(error.localizedDescription)")
                resultError = error
            }
        }

        semaphore.wait()
        reply(resultData, resultError)
    }

    /// Checks for the availability of an interpreter.
    /// - Parameters:
    ///   - language: The language identifier.
    ///   - reply: The completion handler with interpreter info.
    func checkInterpreter(
        _ language: String,
        reply: @escaping (String?, String?, Error?) -> Void
    ) {
        logger.debug("Checking interpreter for \(language)")

        let semaphore = DispatchSemaphore(value: 0)
        var interpreterPath: String?
        var interpreterVersion: String?
        var interpreterError: Error?

        Task {
            defer { semaphore.signal() }
            let (path, version) = await executor.findInterpreter(for: language)
            if let path = path {
                logger.debug("Found \(language) at \(path)")
                interpreterPath = path
                interpreterVersion = version
            } else {
                logger.debug("Interpreter for \(language) not found")
                interpreterError = XPCExecutionError.interpreterNotFound(language)
            }
        }

        semaphore.wait()
        reply(interpreterPath, interpreterVersion, interpreterError)
    }

    /// Retrieves the version of the helper service.
    /// - Parameter reply: The completion handler with the version string.
    func getVersion(reply: @escaping (String) -> Void) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        reply("\(version) (\(build))")
    }

    /// Pings the service to check connectivity.
    /// - Parameter reply: The completion handler with success status.
    func ping(reply: @escaping (Bool) -> Void) {
        logger.debug("Ping received")
        reply(true)
    }
}
#endif
