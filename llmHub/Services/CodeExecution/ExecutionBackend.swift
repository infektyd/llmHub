//
//  ExecutionBackend.swift
//  llmHub
//
//  Protocol abstracting code execution backends
//  Enables XPC (macOS) and remote API (iOS) implementations
//

import Foundation

// MARK: - Execution Backend Protocol

/// Protocol for code execution backends.
/// Abstracts the actual execution mechanism (XPC, remote API, etc.).
protocol ExecutionBackend: Sendable {

    /// Check if the backend is available and ready.
    var isAvailable: Bool { get async }

    /// Execute code and return the result.
    /// - Parameters:
    ///   - code: Source code to execute.
    ///   - language: Programming language.
    ///   - timeout: Maximum execution time in seconds.
    ///   - workingDirectory: Optional working directory.
    /// - Returns: A `CodeExecutionResult`.
    func execute(
        code: String,
        language: SupportedLanguage,
        timeout: Int,
        workingDirectory: URL?
    ) async throws -> CodeExecutionResult

    /// Check if an interpreter is available for the language.
    /// - Parameter language: The language to check.
    /// - Returns: `InterpreterInfo` indicating availability and path.
    func checkInterpreter(for language: SupportedLanguage) async -> InterpreterInfo

    /// Get all available interpreters.
    /// - Returns: Array of `InterpreterInfo` for all languages.
    func checkAllInterpreters() async -> [InterpreterInfo]
}

// MARK: - Backend Factory

/// Factory for creating the appropriate execution backend for the current platform.
enum ExecutionBackendFactory: Sendable {

    /// Create the default backend for the current platform.
    /// - Returns: An instance conforming to `ExecutionBackend`.
    @MainActor
    static func createDefault() -> any ExecutionBackend {
        #if os(macOS)
        print("🔍 [ExecutionBackendFactory] Platform detected: macOS")
        let backend = XPCExecutionBackend()
        print("🔍 [ExecutionBackendFactory] Default backend: XPCExecutionBackend")
        print("🔍 [ExecutionBackendFactory] Backend type: \(type(of: backend))")
        return backend
        #elseif os(iOS)
        print("🔍 [ExecutionBackendFactory] Platform detected: iOS")
        #if canImport(Python)
        print("🔍 [ExecutionBackendFactory] canImport(Python): true")
        #else
        print("🔍 [ExecutionBackendFactory] canImport(Python): false")
        #endif
        let backend = iOSPythonExecutionBackend()
        print("🔍 [ExecutionBackendFactory] Default backend: iOSPythonExecutionBackend")
        print("🔍 [ExecutionBackendFactory] Backend type: \(type(of: backend))")
        return backend
        #else
        print("🔍 [ExecutionBackendFactory] Platform detected: unknown")
        let backend = UnavailableExecutionBackend()
        print("🔍 [ExecutionBackendFactory] Default backend: UnavailableExecutionBackend")
        print("🔍 [ExecutionBackendFactory] Backend type: \(type(of: backend))")
        return backend
        #endif
    }
}

// MARK: - Unavailable Backend (iOS Stub)

/// Placeholder backend for platforms without local execution.
/// Will be replaced with RemoteExecutionBackend in the future.
struct UnavailableExecutionBackend: ExecutionBackend {

    /// Always returns false as this backend represents unavailability.
    var isAvailable: Bool {
        get async { false }
    }

    /// Throws an error indicating execution is not available.
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

    /// Returns unavailable interpreter info.
    func checkInterpreter(for language: SupportedLanguage) async -> InterpreterInfo {
        InterpreterInfo.unavailable(language)
    }

    /// Returns unavailable info for all interpreters.
    func checkAllInterpreters() async -> [InterpreterInfo] {
        SupportedLanguage.allCases.map { InterpreterInfo.unavailable($0) }
    }
}
