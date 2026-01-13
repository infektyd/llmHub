//
//  CodeInterpreterTool.swift
//  llmHub
//
//  Tool implementation for code execution
//

import Foundation
import OSLog

/// Code Interpreter Tool conforming to the Tool protocol.
/// Executes code in Swift, Python, TypeScript, JavaScript, and Dart.
final class CodeInterpreterTool: Tool, @unchecked Sendable {
    let name = "code_interpreter"
    let description = """
        Executes code in various programming languages and returns the output. \
        Supports Swift, Python, TypeScript, JavaScript, and Dart. \
        Use this tool when you need to run code to solve problems, \
        perform calculations, process data, or demonstrate programming concepts.
        """

    nonisolated var parameters: ToolParametersSchema {
        #if os(iOS)
        let supportedLanguages: [SupportedLanguage] = [.javascript]
        #else
        let supportedLanguages: [SupportedLanguage] = SupportedLanguage.allCases
        #endif
        return ToolParametersSchema(
            properties: [
                "code": ToolProperty(
                    type: .string,
                    description: "The code to execute"
                ),
                "language": ToolProperty(
                    type: .string,
                    description: "The programming language of the code",
                    enumValues: supportedLanguages.map { $0.rawValue }
                )
            ],
            required: ["code", "language"]
        )
    }

    // Tool Protocol properties
    nonisolated var permissionLevel: ToolPermissionLevel {
        switch securityMode {
        case .approval: return .dangerous
        case .sandbox: return .sensitive
        case .unrestricted: return .safe
        }
    }

    nonisolated var requiredCapabilities: [ToolCapability] { [.codeExecution] }
    nonisolated var weight: ToolWeight { .heavy }
    nonisolated var isCacheable: Bool { false }

    private let engine: CodeExecutionEngine
    private let environment: ToolEnvironment
    private let logger = Logger(subsystem: "com.llmhub", category: "CodeInterpreterTool")

    // Configuration
    nonisolated(unsafe) var securityMode: CodeSecurityMode = .sandbox
    nonisolated(unsafe) var timeoutSeconds: Int = 30

    // Callback for approval mode
    nonisolated(unsafe) var approvalHandler: ((String, SupportedLanguage) async -> Bool)?

    // Callback for execution events (for UI updates)
    nonisolated(unsafe) var onExecutionStart: ((CodeExecutionRequest) -> Void)?
    nonisolated(unsafe) var onExecutionComplete: ((CodeExecutionResult) -> Void)?

    /// Initialize with a specific engine.
    /// - Parameter engine: The `CodeExecutionEngine` instance.
    init(engine: CodeExecutionEngine, environment: ToolEnvironment = .current) {
        self.engine = engine
        self.environment = environment
    }

    /// Initialize with the default engine (must be called from MainActor).
    @MainActor
    init(environment: ToolEnvironment = .current) {
        self.environment = environment
        self.engine = CodeExecutionEngine()
    }

    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        // ============================================================================
        // 🔍 DIAGNOSTIC BLOCK 1: Tool Entry Point
        // ============================================================================
        print("\n🔍 [CodeInterpreter] ========== EXECUTION STARTED ==========")
        print("🔍 [CodeInterpreter] Timestamp: \(Date())")
        
        #if os(iOS)
        print("🔍 [CodeInterpreter] Platform: iOS (compiled)")
        #elseif os(macOS)
        print("🔍 [CodeInterpreter] Platform: macOS (compiled)")
        #else
        print("🔍 [CodeInterpreter] Platform: Unknown")
        #endif
        
        print("🔍 [CodeInterpreter] Environment checks:")
        print("  ├─ environment.platform: \(environment.platform)")
        print("  ├─ environment.hasCodeExecutionBackend: \(environment.hasCodeExecutionBackend)")
        print("  ├─ environment.supports(.codeExecution): \(environment.supports(.codeExecution))")
        print("  └─ securityMode: \(securityMode)")
        
        // Original capability check
        guard environment.supports(.codeExecution) else {
            print("❌ [CodeInterpreter] FAILED at capability check")
            logger.debug("Code interpreter unavailable on this platform")
            throw ToolError.unavailable(reason: "Code execution unavailable on this platform")
        }
        print("✅ [CodeInterpreter] Passed capability check")
        
        // Original argument extraction
        guard let code = arguments.string("code") else {
            print("❌ [CodeInterpreter] FAILED: Missing 'code' argument")
            throw ToolError.invalidArguments("code is required")
        }
        print("✅ [CodeInterpreter] Extracted code: \(code.count) chars")
        
        guard let languageStr = arguments.string("language"),
            let language = SupportedLanguage(rawValue: languageStr)
        else {
            print("❌ [CodeInterpreter] FAILED: Invalid language argument")
            throw ToolError.invalidArguments(
                "language must be one of \(SupportedLanguage.allCases.map { $0.rawValue }.joined(separator: ", "))"
            )
        }
        print("✅ [CodeInterpreter] Extracted language: \(language.rawValue)")
        
        print("🔍 [CodeInterpreter] Calling executeCode()...")
        // ============================================================================
        
        let output = try await executeCode(code: code, language: language)
        
        print("✅ [CodeInterpreter] executeCode() returned successfully")
        print("🔍 [CodeInterpreter] ========== EXECUTION COMPLETED ==========\n")
        
        return await MainActor.run {
            ToolResult.success(output)
        }
    }

    /// Execute code and return formatted result.
    /// - Parameters:
    ///   - code: The code to execute.
    ///   - language: The programming language.
    /// - Returns: A summary string of the execution result.
    func executeCode(code: String, language: SupportedLanguage) async throws -> String {
        print("\n🔍 [executeCode] ========== METHOD ENTRY ==========")
        print("🔍 [executeCode] Language: \(language.rawValue)")
        print("🔍 [executeCode] Code length: \(code.count) chars")
        print("🔍 [executeCode] Security mode: \(securityMode)")
        print("🔍 [executeCode] Timeout: \(timeoutSeconds)s")

        #if os(iOS)
        if language != .javascript {
            throw ToolError.executionFailed(
                "Only JavaScript is supported for code execution on iOS. Python/Swift/TypeScript/Dart require macOS.",
                retryable: false
            )
        }
        #endif
        
        logger.info("Executing \(language.rawValue) code (\(code.count) chars)")

        // Check for approval if required
        if securityMode == .approval {
            print("🔍 [executeCode] Approval mode - checking handler...")
            guard let handler = approvalHandler else {
                print("❌ [executeCode] FAILED: No approval handler set")
                throw CodeExecutionError.approvalDenied
            }

            print("🔍 [executeCode] Requesting user approval...")
            let approved = await handler(code, language)
            if !approved {
                print("❌ [executeCode] FAILED: User denied approval")
                throw CodeExecutionError.approvalDenied
            }
            print("✅ [executeCode] User approved execution")
        }

        let request = CodeExecutionRequest(
            language: language,
            code: code,
            timeoutSeconds: timeoutSeconds
        )
        print("✅ [executeCode] Created CodeExecutionRequest: \(request.id)")

        // Notify start
        print("🔍 [executeCode] Calling onExecutionStart callback...")
        onExecutionStart?(request)

        do {
            print("🔍 [executeCode] Calling engine.execute()...")
            let result = try await engine.execute(
                request: request,
                securityMode: securityMode
            )
            print("✅ [executeCode] engine.execute() returned")
            print("🔍 [executeCode] Result: exitCode=\(result.exitCode), time=\(result.executionTimeMs)ms")

            // Notify completion
            onExecutionComplete?(result)

            let workspaceID = CloudWorkspaceManager.shared.defaultWorkspaceID()
            Task.detached(priority: .utility) {
                try? await CloudWorkspaceManager.shared.saveExecutionOutput(
                    result: result,
                    toWorkspace: workspaceID
                )
            }

            logger.info(
                "Execution completed: exit=\(result.exitCode), time=\(result.executionTimeMs)ms")
            
            print("🔍 [executeCode] ========== METHOD EXIT (SUCCESS) ==========\n")
            return result.llmSummary

        } catch let error as CodeExecutionError {
            print("❌ [executeCode] Caught CodeExecutionError: \(error.localizedDescription)")
            logger.error("Execution failed: \(error.localizedDescription)")
            if case .timeout(let seconds) = error {
                throw ToolError.timeout(after: TimeInterval(seconds))
            }
            throw ToolError.executionFailed(error.localizedDescription, retryable: false)
        } catch {
            print("❌ [executeCode] Caught unexpected error: \(error)")
            throw error
        }
    }

    /// Get detailed result object (for UI display).
    /// - Parameters:
    ///   - code: The code to execute.
    ///   - language: The programming language.
    /// - Returns: A `CodeExecutionResult` object.
    func executeWithResult(code: String, language: SupportedLanguage) async throws
        -> CodeExecutionResult {
        // Check for approval if required
        if securityMode == .approval {
            guard let handler = approvalHandler else {
                throw CodeExecutionError.approvalDenied
            }

            let approved = await handler(code, language)
            if !approved {
                throw CodeExecutionError.approvalDenied
            }
        }

        let request = CodeExecutionRequest(
            language: language,
            code: code,
            timeoutSeconds: timeoutSeconds
        )

        onExecutionStart?(request)

        let result = try await engine.execute(
            request: request,
            securityMode: securityMode
        )

        onExecutionComplete?(result)

        let workspaceID = CloudWorkspaceManager.shared.defaultWorkspaceID()
        Task.detached(priority: .utility) {
            try? await CloudWorkspaceManager.shared.saveExecutionOutput(
                result: result,
                toWorkspace: workspaceID
            )
        }

        return result
    }

    // MARK: - Availability
    // Properties are defined in protocol conformance

    /// Check which interpreters are available.
    /// - Returns: An array of `InterpreterInfo`.
    func checkAvailability() async -> [InterpreterInfo] {
        await engine.checkAllInterpreters()
    }
}

// MARK: - Quick Execution Helper

extension CodeInterpreterTool {
    /// Quick Python calculation.
    /// - Parameter code: Python code to run.
    /// - Returns: Execution output.
    @MainActor
    static func quickPython(_ code: String) async throws -> String {
        let tool = CodeInterpreterTool()
        tool.securityMode = .unrestricted
        tool.timeoutSeconds = 10
        return try await tool.executeCode(code: code, language: .python)
    }

    /// Quick Swift calculation.
    /// - Parameter code: Swift code to run.
    /// - Returns: Execution output.
    @MainActor
    static func quickSwift(_ code: String) async throws -> String {
        let tool = CodeInterpreterTool()
        tool.securityMode = .unrestricted
        tool.timeoutSeconds = 10
        return try await tool.executeCode(code: code, language: .swift)
    }
}

// MARK: - Code Validation (Optional Pre-check)

extension CodeInterpreterTool {
    /// Basic syntax validation hints.
    /// - Parameters:
    ///   - code: The code to validate.
    ///   - language: The programming language.
    /// - Returns: A list of warning messages.
    func validateCode(_ code: String, language: SupportedLanguage) -> [String] {
        var warnings: [String] = []

        // Check for potentially dangerous patterns (varies slightly by language)
        var dangerousPatterns: [(pattern: String, warning: String)] = [
            ("rm -rf", "⚠️ Code contains 'rm -rf' which can delete files"),
            ("system\\(", "⚠️ Code uses system() which can execute shell commands"),
            ("exec\\(", "⚠️ Code uses exec() which can execute arbitrary commands"),
            ("eval\\(", "⚠️ Code uses eval() which can execute arbitrary code")
        ]

        // Add language-specific patterns
        switch language {
        case .swift:
            dangerousPatterns.append(
                ("Process\\(", "⚠️ Code uses Process which can spawn subprocesses"))
            dangerousPatterns.append(
                ("FileManager", "⚠️ Code uses FileManager (file system access)"))
        case .python:
            dangerousPatterns.append(
                ("import os", "⚠️ Code imports 'os' module (file system access)"))
            dangerousPatterns.append(
                ("import subprocess", "⚠️ Code imports 'subprocess' (shell access)"))
        case .javascript, .typescript:
            dangerousPatterns.append(
                ("require\\(['\"]child_process", "⚠️ Code uses child_process (shell access)"))
            dangerousPatterns.append(
                ("require\\(['\"]fs", "⚠️ Code uses fs module (file system access)"))
        case .dart:
            dangerousPatterns.append(
                ("import 'dart:io'", "⚠️ Code imports dart:io (file system/process access)"))
        }

        for (pattern, warning) in dangerousPatterns {
            if code.contains(pattern) || code.range(of: pattern, options: .regularExpression) != nil {
                warnings.append(warning)
            }
        }

        // Check for infinite loop patterns
        let infiniteLoopPatterns = [
            "while true",
            "while True",
            "while 1",
            "for \\(;;\\)",
            "loop \\{"
        ]

        for pattern in infiniteLoopPatterns where code.range(of: pattern, options: .regularExpression) != nil {
            warnings.append("⚠️ Code may contain an infinite loop")
            break
        }

        return warnings
    }
}
