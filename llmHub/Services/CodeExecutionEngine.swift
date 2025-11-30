//
//  CodeExecutionEngine.swift
//  llmHub
//
//  Core execution engine using pluggable backends
//  Uses XPC on macOS, remote API on iOS/iPadOS
//

import Foundation
import OSLog

/// Code execution engine that delegates to platform-specific backends
/// On macOS: Uses XPC service for local execution outside sandbox
/// On iOS/iPadOS: Will use remote API (future implementation)
actor CodeExecutionEngine {
    private let logger = Logger(subsystem: "com.llmhub", category: "CodeExecutionEngine")
    private let backend: any ExecutionBackend
    private let sandboxManager: SandboxManager
    private var interpreterCache: [SupportedLanguage: InterpreterInfo] = [:]
    
    /// Initialize with a specific backend
    init(
        backend: any ExecutionBackend,
        sandboxManager: SandboxManager = SandboxManager()
    ) {
        self.backend = backend
        self.sandboxManager = sandboxManager
    }
    
    /// Initialize with the default backend for the current platform
    /// This initializer must be called from MainActor context
    @MainActor
    init(sandboxManager: SandboxManager = SandboxManager()) {
        self.backend = ExecutionBackendFactory.createDefault()
        self.sandboxManager = sandboxManager
    }
    
    // MARK: - Backend Status
    
    /// Check if the execution backend is available
    var isBackendAvailable: Bool {
        get async {
            await backend.isAvailable
        }
    }
    
    // MARK: - Interpreter Discovery
    
    /// Find the interpreter for a language
    func findInterpreter(for language: SupportedLanguage) async -> InterpreterInfo {
        // Check cache first
        if let cached = interpreterCache[language] {
            return cached
        }
        
        let info = await backend.checkInterpreter(for: language)
        interpreterCache[language] = info
        return info
    }
    
    /// Check availability of all interpreters
    func checkAllInterpreters() async -> [InterpreterInfo] {
        let results = await backend.checkAllInterpreters()
        
        // Update cache
        for info in results {
            interpreterCache[info.language] = info
        }
        
        return results
    }
    
    // MARK: - Code Execution
    
    /// Execute code with the given request
    func execute(
        request: CodeExecutionRequest,
        securityMode: CodeSecurityMode
    ) async throws -> CodeExecutionResult {
        let languageName = request.language.rawValue
        let codeLength = request.code.count
        logger.info("Executing \(languageName) code (\(codeLength) chars)")
        
        // Check backend availability
        guard await backend.isAvailable else {
            throw CodeExecutionError.processLaunchFailed(
                "Code execution backend is not available. Please ensure the helper service is running."
            )
        }
        
        // Find interpreter first to give early feedback
        let interpreter = await findInterpreter(for: request.language)
        guard interpreter.isAvailable else {
            throw CodeExecutionError.interpreterNotFound(request.language)
        }
        
        // Determine working directory
        var workingDirectory: URL?
        let isSandboxMode = securityMode.rawValue == CodeSecurityMode.sandbox.rawValue
        if isSandboxMode {
            // Create a sandbox directory for output files
            workingDirectory = try await sandboxManager.createSandbox(for: request.id)
        }
        
        do {
            // Execute via backend
            let result = try await backend.execute(
                code: request.code,
                language: request.language,
                timeout: request.timeoutSeconds,
                workingDirectory: workingDirectory
            )
            
            logger.info("Execution completed: exit=\(result.exitCode), time=\(result.executionTimeMs)ms")
            
            // Cleanup sandbox after delay
            if isSandboxMode {
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    await sandboxManager.cleanupSandbox(for: request.id)
                }
            }
            
            return result
            
        } catch {
            // Cleanup sandbox on error
            if isSandboxMode {
                await sandboxManager.cleanupSandbox(for: request.id)
            }
            throw error
        }
    }
    
    // MARK: - Quick Execution
    
    /// Quick execution for trusted code snippets
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
    /// Start an interactive REPL session (placeholder for future implementation)
    func startREPL(for language: SupportedLanguage) async throws -> UUID {
        throw CodeExecutionError.processLaunchFailed("REPL not yet implemented")
    }
}
