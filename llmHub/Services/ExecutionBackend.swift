//
//  ExecutionBackend.swift
//  llmHub
//
//  Protocol abstracting code execution backends
//  Enables XPC (macOS) and remote API (iOS) implementations
//

import Foundation

// MARK: - Execution Backend Protocol

/// Protocol for code execution backends
/// Abstracts the actual execution mechanism (XPC, remote API, etc.)
protocol ExecutionBackend: Sendable {
    
    /// Check if the backend is available and ready
    var isAvailable: Bool { get async }
    
    /// Execute code and return the result
    /// - Parameters:
    ///   - code: Source code to execute
    ///   - language: Programming language
    ///   - timeout: Maximum execution time in seconds
    ///   - workingDirectory: Optional working directory
    /// - Returns: Execution result
    func execute(
        code: String,
        language: SupportedLanguage,
        timeout: Int,
        workingDirectory: URL?
    ) async throws -> CodeExecutionResult
    
    /// Check if an interpreter is available for the language
    /// - Parameter language: The language to check
    /// - Returns: Interpreter info if available
    func checkInterpreter(for language: SupportedLanguage) async -> InterpreterInfo
    
    /// Get all available interpreters
    /// - Returns: Array of interpreter info for all languages
    func checkAllInterpreters() async -> [InterpreterInfo]
}

// MARK: - Backend Factory

/// Factory for creating the appropriate execution backend for the current platform
enum ExecutionBackendFactory: Sendable {
    
    /// Create the default backend for the current platform
    @MainActor
    static func createDefault() -> any ExecutionBackend {
        #if os(macOS)
        return XPCExecutionBackend()
        #else
        // iOS/iPadOS would use RemoteExecutionBackend
        // For now, return a stub that explains the limitation
        return UnavailableExecutionBackend()
        #endif
    }
}

// MARK: - Unavailable Backend (iOS Stub)

/// Placeholder backend for platforms without local execution
/// Will be replaced with RemoteExecutionBackend in the future
struct UnavailableExecutionBackend: ExecutionBackend {
    
    var isAvailable: Bool {
        get async { false }
    }
    
    func execute(
        code: String,
        language: SupportedLanguage,
        timeout: Int,
        workingDirectory: URL?
    ) async throws -> CodeExecutionResult {
        throw CodeExecutionError.processLaunchFailed(
            "Code execution is not available on this platform. " +
            "A remote execution API will be added in a future update."
        )
    }
    
    func checkInterpreter(for language: SupportedLanguage) async -> InterpreterInfo {
        InterpreterInfo.unavailable(language)
    }
    
    func checkAllInterpreters() async -> [InterpreterInfo] {
        SupportedLanguage.allCases.map { InterpreterInfo.unavailable($0) }
    }
}

