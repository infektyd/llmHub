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
    nonisolated let id = "code_interpreter"
    nonisolated let name = "code_interpreter"
    nonisolated let description = """
        Executes code in various programming languages and returns the output. \
        Supports Swift, Python, TypeScript, JavaScript, and Dart. \
        Use this tool when you need to run code to solve problems, \
        perform calculations, process data, or demonstrate programming concepts.
        """

    nonisolated var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "code": [
                    "type": "string",
                    "description": "The code to execute",
                ],
                "language": [
                    "type": "string",
                    "enum": SupportedLanguage.allCases.map { $0.rawValue },
                    "description": "The programming language of the code",
                ],
            ],
            "required": ["code", "language"],
        ]
    }

    private let engine: CodeExecutionEngine
    private let logger = Logger(subsystem: "com.llmhub", category: "CodeInterpreterTool")

    // Configuration
    var securityMode: CodeSecurityMode = .sandbox
    var timeoutSeconds: Int = 30

    // Callback for approval mode
    var approvalHandler: ((String, SupportedLanguage) async -> Bool)?

    // Callback for execution events (for UI updates)
    var onExecutionStart: ((CodeExecutionRequest) -> Void)?
    var onExecutionComplete: ((CodeExecutionResult) -> Void)?

    /// Initialize with a specific engine.
    /// - Parameter engine: The `CodeExecutionEngine` instance.
    init(engine: CodeExecutionEngine) {
        self.engine = engine
    }

    /// Initialize with the default engine (must be called from MainActor).
    @MainActor
    init() {
        self.engine = CodeExecutionEngine()
    }

    nonisolated func execute(input: [String: Any]) async throws -> String {
        guard let code = input["code"] as? String else {
            throw ToolError.invalidInput
        }

        guard let languageStr = input["language"] as? String,
            let language = SupportedLanguage(rawValue: languageStr)
        else {
            throw ToolError.invalidInput
        }

        return try await executeCode(code: code, language: language)
    }

    /// Execute code and return formatted result.
    /// - Parameters:
    ///   - code: The code to execute.
    ///   - language: The programming language.
    /// - Returns: A summary string of the execution result.
    func executeCode(code: String, language: SupportedLanguage) async throws -> String {
        logger.info("Executing \(language.displayName) code (\(code.count) chars)")

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

        // Notify start
        onExecutionStart?(request)

        do {
            let result = try await engine.execute(
                request: request,
                securityMode: securityMode
            )

            // Notify completion
            onExecutionComplete?(result)

            logger.info(
                "Execution completed: exit=\(result.exitCode), time=\(result.executionTimeMs)ms")

            return result.llmSummary

        } catch let error as CodeExecutionError {
            logger.error("Execution failed: \(error.localizedDescription)")
            throw ToolError.executionFailed(error.localizedDescription)
        }
    }

    /// Get detailed result object (for UI display).
    /// - Parameters:
    ///   - code: The code to execute.
    ///   - language: The programming language.
    /// - Returns: A `CodeExecutionResult` object.
    func executeWithResult(code: String, language: SupportedLanguage) async throws
        -> CodeExecutionResult
    {
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

        return result
    }

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
    static func quickPython(_ code: String) async throws -> String {
        let tool = await CodeInterpreterTool()
        tool.securityMode = .unrestricted
        tool.timeoutSeconds = 10
        return try await tool.executeCode(code: code, language: .python)
    }

    /// Quick Swift calculation.
    /// - Parameter code: Swift code to run.
    /// - Returns: Execution output.
    static func quickSwift(_ code: String) async throws -> String {
        let tool = await CodeInterpreterTool()
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
            ("eval\\(", "⚠️ Code uses eval() which can execute arbitrary code"),
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
            if code.contains(pattern) || code.range(of: pattern, options: .regularExpression) != nil
            {
                warnings.append(warning)
            }
        }

        // Check for infinite loop patterns
        let infiniteLoopPatterns = [
            "while true",
            "while True",
            "while 1",
            "for \\(;;\\)",
            "loop \\{",
        ]

        for pattern in infiniteLoopPatterns {
            if code.range(of: pattern, options: .regularExpression) != nil {
                warnings.append("⚠️ Code may contain an infinite loop")
                break
            }
        }

        return warnings
    }
}
