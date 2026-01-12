//
//  CodeExecutionXPCProtocol.swift
//  llmHubHelper
//
//  XPC Protocol for code execution communication between main app and helper
//  This file is shared between the main app and the XPC service
//

import Foundation

// MARK: - XPC Protocol

/// Protocol defining the XPC interface for code execution.
/// The helper implements this, and the main app calls it via XPC.
@objc(CodeExecutionXPCProtocol) public protocol CodeExecutionXPCProtocol {

    /// Execute code in the specified language.
    /// - Parameters:
    ///   - code: The source code to execute.
    ///   - language: Language identifier (swift, python, javascript, typescript, dart).
    ///   - timeout: Maximum execution time in seconds.
    ///   - workingDirectory: Optional working directory path.
    ///   - reply: Callback with JSON-encoded result data or error.
    func executeCode(
        _ code: String,
        language: String,
        timeout: Int,
        workingDirectory: String?,
        reply: @escaping (Data?, Error?) -> Void
    )

    /// Check if an interpreter is available for the given language.
    /// - Parameters:
    ///   - language: Language identifier.
    ///   - reply: Callback with interpreter path, version string, or error.
    func checkInterpreter(
        _ language: String,
        reply: @escaping (String?, String?, Error?) -> Void
    )

    /// Get the version of the XPC helper.
    /// - Parameter reply: Callback with version string.
    func getVersion(reply: @escaping (String) -> Void)

    /// Ping to verify connection is alive.
    /// - Parameter reply: Callback confirming connection.
    func ping(reply: @escaping (Bool) -> Void)
}

// MARK: - XPC Result Types

/// Result of code execution, Codable for XPC transfer.
public struct XPCExecutionResult: Codable, Sendable {
    /// The execution request ID.
    public let id: String
    /// The language used.
    public let language: String
    /// The standard output content.
    public let stdout: String
    /// The standard error content.
    public let stderr: String
    /// The process exit code.
    public let exitCode: Int32
    /// The execution time in milliseconds.
    public let executionTimeMs: Int
    /// The path of the interpreter used.
    public let interpreterPath: String?

    /// Initializes a new `XPCExecutionResult`.
    public init(
        id: String,
        language: String,
        stdout: String,
        stderr: String,
        exitCode: Int32,
        executionTimeMs: Int,
        interpreterPath: String?
    ) {
        self.id = id
        self.language = language
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.executionTimeMs = executionTimeMs
        self.interpreterPath = interpreterPath
    }

    /// Indicates if execution was successful (exit code 0).
    public var isSuccess: Bool {
        exitCode == 0
    }
}

// MARK: - XPC Errors

/// Errors that can occur during XPC code execution.
public enum XPCExecutionError: LocalizedError, Codable, Sendable {
    /// The language interpreter was not found.
    case interpreterNotFound(String)
    /// Execution exceeded the timeout limit.
    case timeout(Int)
    /// Failed to launch the process.
    case processLaunchFailed(String)
    /// The requested language is invalid or unsupported.
    case invalidLanguage(String)
    /// Failed to write the code to a file.
    case fileWriteFailed(String)
    /// The XPC connection failed.
    case connectionFailed
    /// The response from the helper was invalid.
    case invalidResponse

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .interpreterNotFound(let lang):
            return "Interpreter for \(lang) not found"
        case .timeout(let seconds):
            return "Execution timed out after \(seconds) seconds"
        case .processLaunchFailed(let reason):
            return "Failed to launch process: \(reason)"
        case .invalidLanguage(let lang):
            return "Invalid language: \(lang)"
        case .fileWriteFailed(let reason):
            return "Failed to write code file: \(reason)"
        case .connectionFailed:
            return "XPC connection failed"
        case .invalidResponse:
            return "Invalid response from helper"
        }
    }
}

// MARK: - XPC Service Identifier

/// The Mach service name for the XPC helper.
/// Must match the bundle identifier of the XPC service.
public let kCodeExecutionXPCServiceName = "Syntra.llmHub.CodeExecutionHelper"
