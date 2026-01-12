//
//  CodeExecutionEngine.swift
//  llmHub
//
//  Core execution engine using pluggable backends
//  Uses XPC on macOS, remote API on iOS/iPadOS
//

import Foundation
import OSLog

/// Code execution engine that delegates to platform-specific backends.
/// On macOS: Uses XPC service for local execution outside sandbox.
/// On iOS/iPadOS: Will use remote API (future implementation).
actor CodeExecutionEngine {
    private let logger = Logger(subsystem: "com.llmhub", category: "CodeExecutionEngine")
    private let backend: any ExecutionBackend
    private let sandboxManager: SandboxManager
    private var interpreterCache: [SupportedLanguage: InterpreterInfo] = [:]

    /// Initialize with a specific backend.
    /// - Parameters:
    ///   - backend: The backend to use.
    ///   - sandboxManager: The sandbox manager (default: new instance).
    init(
        backend: any ExecutionBackend,
        sandboxManager: SandboxManager = SandboxManager()
    ) {
        self.backend = backend
        self.sandboxManager = sandboxManager
    }

    /// Initialize with the default backend for the current platform.
    /// This initializer must be called from MainActor context.
    /// - Parameter sandboxManager: The sandbox manager.
    @MainActor
    init(sandboxManager: SandboxManager = SandboxManager()) {
        self.backend = ExecutionBackendFactory.createDefault()
        self.sandboxManager = sandboxManager
    }

    // MARK: - Backend Status

    /// Check if the execution backend is available.
    var isBackendAvailable: Bool {
        get async {
            await backend.isAvailable
        }
    }

    // MARK: - Interpreter Discovery

    /// Find the interpreter for a language.
    /// - Parameter language: The language to find.
    /// - Returns: `InterpreterInfo` containing availability and path.
    func findInterpreter(for language: SupportedLanguage) async -> InterpreterInfo {
        // Check cache first
        if let cached = interpreterCache[language] {
            return cached
        }

        let info = await backend.checkInterpreter(for: language)
        interpreterCache[language] = info
        return info
    }

    /// Check availability of all interpreters.
    /// - Returns: A list of `InterpreterInfo` for all supported languages.
    func checkAllInterpreters() async -> [InterpreterInfo] {
        let results = await backend.checkAllInterpreters()

        // Update cache
        for info in results {
            interpreterCache[info.language] = info
        }

        return results
    }

    // MARK: - Code Execution

    /// Execute code with the given request.
    /// - Parameters:
    ///   - request: The execution request.
    ///   - securityMode: The security mode to enforce.
    /// - Returns: A `CodeExecutionResult` object.
    func execute(
        request: CodeExecutionRequest,
        securityMode: CodeSecurityMode
    ) async throws -> CodeExecutionResult {
        print("\n🔍 [Engine] ========== ENGINE EXECUTE CALLED ==========")
        print("🔍 [Engine] Request ID: \(request.id)")
        print("🔍 [Engine] Language: \(request.language.rawValue)")
        print("🔍 [Engine] Code length: \(request.code.count) chars")
        print("🔍 [Engine] Security mode: \(securityMode)")
        print("🔍 [Engine] Timeout: \(request.timeoutSeconds)s")
        
        let languageName = request.language.rawValue
        let codeLength = request.code.count
        logger.info("Executing \(languageName) code (\(codeLength) chars)")

        // Check backend availability
        print("🔍 [Engine] Checking backend availability...")
        let isAvailable = await backend.isAvailable
        print("🔍 [Engine] Backend isAvailable: \(isAvailable)")
        
        guard isAvailable else {
            print("❌ [Engine] FAILED: Backend not available")
            throw CodeExecutionError.processLaunchFailed(
                "Code execution backend is not available. Please ensure the helper service is running."
            )
        }
        print("✅ [Engine] Backend is available")

        // Find interpreter first to give early feedback
        print("🔍 [Engine] Finding interpreter for \(request.language.rawValue)...")
        let interpreter = await findInterpreter(for: request.language)
        print("🔍 [Engine] Interpreter check:")
        print("  ├─ isAvailable: \(interpreter.isAvailable)")
        print("  ├─ path: \(interpreter.path ?? "nil")")
        print("  └─ version: \(interpreter.version ?? "nil")")
        
        guard interpreter.isAvailable else {
            print("❌ [Engine] FAILED: Interpreter not found")
            throw CodeExecutionError.interpreterNotFound(request.language)
        }
        print("✅ [Engine] Interpreter available")

        // Determine working directory
        var workingDirectory: URL?
        let isSandboxMode = securityMode.rawValue == CodeSecurityMode.sandbox.rawValue
        print("🔍 [Engine] isSandboxMode: \(isSandboxMode)")
        
        if isSandboxMode {
            print("🔍 [Engine] Creating sandbox for request \(request.id)...")
            // Create a sandbox directory for output files
            workingDirectory = try await sandboxManager.createSandbox(for: request.id)
            print("✅ [Engine] Sandbox created at: \(workingDirectory?.path ?? "nil")")
        }

        do {
            print("🔍 [Engine] Calling backend.execute()...")
            // Execute via backend
            let result = try await backend.execute(
                code: request.code,
                language: request.language,
                timeout: request.timeoutSeconds,
                workingDirectory: workingDirectory
            )
            print("✅ [Engine] backend.execute() returned")
            print("🔍 [Engine] Result: exitCode=\(result.exitCode), time=\(result.executionTimeMs)ms")

            logger.info("Execution completed: exit=\(result.exitCode), time=\(result.executionTimeMs)ms")

            // Cleanup sandbox after delay
            if isSandboxMode {
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    await sandboxManager.cleanupSandbox(for: request.id)
                }
            }
            
            print("🔍 [Engine] ========== ENGINE EXECUTE COMPLETED ==========\n")
            return result

        } catch {
            print("❌ [Engine] Caught error: \(error)")
            // Cleanup sandbox on error
            if isSandboxMode {
                await sandboxManager.cleanupSandbox(for: request.id)
            }
            throw error
        }
    }

    // MARK: - Quick Execution

    /// Quick execution for trusted code snippets.
    /// - Parameters:
    ///   - code: The code to execute.
    ///   - language: The programming language.
    /// - Returns: The combined stdout and stderr output.
    nonisolated func quickExecute(code: String, language: SupportedLanguage) async throws -> String {
        let request = CodeExecutionRequest(
            id: UUID(),
            language: language,
            code: code,
            timeoutSeconds: 10,
            workingDirectory: nil
        )

        let result = try await execute(request: request, securityMode: .unrestricted)
        return result.stdout.isEmpty ? result.stderr : result.stdout + (result.stderr.isEmpty ? "" : "\n" + result.stderr)
    }
}

// MARK: - REPL Support (Future)

extension CodeExecutionEngine {
    /// Start an interactive REPL session (placeholder for future implementation).
    /// - Parameter language: The language for the REPL.
    /// - Returns: The session ID.
    func startREPL(for language: SupportedLanguage) async throws -> UUID {
        throw CodeExecutionError.processLaunchFailed("REPL not yet implemented")
    }
}
