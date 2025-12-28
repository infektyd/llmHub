//
//  CodeExecutionModels.swift
//  llmHub
//
//  Created for Code Interpreter feature
//

import Foundation

// MARK: - Supported Languages

/// Enum representing the programming languages supported by the code execution engine.
enum SupportedLanguage: String, CaseIterable, Codable, Sendable {
    /// Swift language.
    case swift
    /// Python language.
    case python
    /// TypeScript language.
    case typescript
    /// JavaScript language.
    case javascript
    /// Dart language.
    case dart

    /// The display name of the language (e.g., "Python").
    var displayName: String {
        switch self {
        case .swift: return "Swift"
        case .python: return "Python"
        case .typescript: return "TypeScript"
        case .javascript: return "JavaScript"
        case .dart: return "Dart"
        }
    }

    /// Nonisolated accessor for display name (safe for use in error descriptions).
    nonisolated var displayNameValue: String {
        switch self {
        case .swift: return "Swift"
        case .python: return "Python"
        case .typescript: return "TypeScript"
        case .javascript: return "JavaScript"
        case .dart: return "Dart"
        }
    }

    /// The standard file extension for the language (e.g., ".py").
    var fileExtension: String {
        switch self {
        case .swift: return ".swift"
        case .python: return ".py"
        case .typescript: return ".ts"
        case .javascript: return ".js"
        case .dart: return ".dart"
        }
    }

    /// Nonisolated version for use in actors.
    nonisolated var fileExtensionValue: String {
        switch self {
        case .swift: return ".swift"
        case .python: return ".py"
        case .typescript: return ".ts"
        case .javascript: return ".js"
        case .dart: return ".dart"
        }
    }

    /// The command-line name of the interpreter (e.g., "python3").
    var interpreterName: String {
        switch self {
        case .swift: return "swift"
        case .python: return "python3"
        case .typescript: return "ts-node"
        case .javascript: return "node"
        case .dart: return "dart"
        }
    }

    /// Nonisolated accessor for interpreter name (safe for use in error descriptions).
    nonisolated var interpreterNameValue: String {
        switch self {
        case .swift: return "swift"
        case .python: return "python3"
        case .typescript: return "ts-node"
        case .javascript: return "node"
        case .dart: return "dart"
        }
    }

    /// Detect language from file extension.
    /// - Parameter ext: The file extension (with or without dot).
    /// - Returns: The matching `SupportedLanguage` or nil if not found.
    static func from(extension ext: String) -> SupportedLanguage? {
        let normalized = ext.lowercased().hasPrefix(".") ? ext.lowercased() : ".\(ext.lowercased())"
        return allCases.first { $0.fileExtension == normalized }
    }

    /// Detect language from filename.
    /// - Parameter filename: The full filename.
    /// - Returns: The matching `SupportedLanguage` or nil if not found.
    static func from(filename: String) -> SupportedLanguage? {
        let ext = (filename as NSString).pathExtension
        return from(extension: ext)
    }
}

// MARK: - Security Mode

/// Defines the security level for code execution.
enum CodeSecurityMode: String, CaseIterable, Codable, Sendable {
    /// Sandbox mode: executes in isolated temp directory.
    case sandbox
    /// Approval mode: requires user confirmation before execution.
    case approval
    /// Unrestricted mode: direct execution with full system access.
    case unrestricted

    /// The display name for the security mode.
    var displayName: String {
        switch self {
        case .sandbox: return "Sandbox"
        case .approval: return "Require Approval"
        case .unrestricted: return "Unrestricted"
        }
    }

    /// A description of the security mode.
    var description: String {
        switch self {
        case .sandbox:
            return "Execute in isolated temp directory with restricted file access"
        case .approval:
            return "Show confirmation dialog before each execution"
        case .unrestricted:
            return "Direct execution with full system access (power user)"
        }
    }

    /// The system image name for the security mode icon.
    var systemImage: String {
        switch self {
        case .sandbox: return "lock.shield"
        case .approval: return "checkmark.shield"
        case .unrestricted: return "exclamationmark.shield"
        }
    }
}

// MARK: - Execution Result

/// Represents the result of a code execution.
struct CodeExecutionResult: Codable, Sendable {
    /// The unique identifier of the execution result.
    let id: UUID
    /// The language of the executed code.
    let language: SupportedLanguage
    /// The executed code.
    let code: String
    /// The standard output of the execution.
    let stdout: String
    /// The standard error of the execution.
    let stderr: String
    /// The exit code of the process.
    let exitCode: Int32
    /// The execution time in milliseconds.
    let executionTimeMs: Int
    /// The timestamp when the execution finished.
    let timestamp: Date
    /// The path to the sandbox used, if any.
    let sandboxPath: String?

    /// Indicates if the execution was successful (exit code 0).
    nonisolated var isSuccess: Bool {
        exitCode == 0
    }

    /// Combines stdout and stderr into a single string.
    var combinedOutput: String {
        var output = ""
        if !stdout.isEmpty {
            output += stdout
        }
        if !stderr.isEmpty {
            if !output.isEmpty { output += "\n" }
            output += stderr
        }
        return output.isEmpty ? "(No output)" : output
    }

    /// Formats the result for inclusion in LLM context.
    nonisolated var llmSummary: String {
        """
        Language: \(language.displayNameValue)
        Exit Code: \(exitCode) (\(isSuccess ? "Success" : "Failed"))
        Execution Time: \(executionTimeMs)ms

        --- STDOUT ---
        \(stdout.isEmpty ? "(empty)" : stdout)

        --- STDERR ---
        \(stderr.isEmpty ? "(empty)" : stderr)
        """
    }
}

// MARK: - Interpreter Info

/// Contains information about a language interpreter.
struct InterpreterInfo: Sendable {
    /// The language supported by the interpreter.
    let language: SupportedLanguage
    /// The file system path to the interpreter.
    let path: String
    /// The version string of the interpreter.
    let version: String?
    /// Indicates if the interpreter is available on the system.
    let isAvailable: Bool

    /// Creates an `InterpreterInfo` instance representing an unavailable interpreter.
    /// - Parameter language: The language that is unavailable.
    /// - Returns: An `InterpreterInfo` instance.
    static func unavailable(_ language: SupportedLanguage) -> InterpreterInfo {
        InterpreterInfo(language: language, path: "", version: nil, isAvailable: false)
    }
}

// MARK: - Execution Request

/// Represents a request to execute code.
struct CodeExecutionRequest: Sendable {
    /// The unique identifier of the request.
    let id: UUID
    /// The language of the code to execute.
    let language: SupportedLanguage
    /// The code content to execute.
    let code: String
    /// The timeout duration in seconds.
    let timeoutSeconds: Int
    /// The working directory for execution.
    let workingDirectory: URL?

    /// Initializes a new `CodeExecutionRequest`.
    /// - Parameters:
    ///   - id: The unique identifier.
    ///   - language: The language of the code.
    ///   - code: The code content.
    ///   - timeoutSeconds: The timeout in seconds (default: 30).
    ///   - workingDirectory: The working directory (optional).
    nonisolated init(
        id: UUID = UUID(),
        language: SupportedLanguage,
        code: String,
        timeoutSeconds: Int = 30,
        workingDirectory: URL? = nil
    ) {
        self.id = id
        self.language = language
        self.code = code
        self.timeoutSeconds = timeoutSeconds
        self.workingDirectory = workingDirectory
    }
}

// MARK: - Execution Errors

/// Errors that can occur during code execution.
enum CodeExecutionError: LocalizedError, Sendable {
    /// The interpreter for the requested language was not found.
    case interpreterNotFound(SupportedLanguage)
    /// The execution timed out.
    case timeout(seconds: Int)
    /// Failed to create the sandbox directory.
    case sandboxCreationFailed(String)
    /// Failed to write the code file.
    case fileWriteFailed(String)
    /// Failed to launch the process.
    case processLaunchFailed(String)
    /// The execution was cancelled.
    case executionCancelled
    /// The user denied approval for execution.
    case approvalDenied

    /// A localized description of the error.
    var errorDescription: String? {
        switch self {
        case .interpreterNotFound(let lang):
            return
                "Interpreter for \(lang.displayNameValue) not found. Please install \(lang.interpreterNameValue)."
        case .timeout(let seconds):
            return "Execution timed out after \(seconds) seconds"
        case .sandboxCreationFailed(let reason):
            return "Failed to create sandbox: \(reason)"
        case .fileWriteFailed(let reason):
            return "Failed to write code file: \(reason)"
        case .processLaunchFailed(let reason):
            return "Failed to launch process: \(reason)"
        case .executionCancelled:
            return "Execution was cancelled"
        case .approvalDenied:
            return "Execution was denied by user"
        }
    }
}

// MARK: - Code File Attachment

/// Represents a code file attached to a chat or execution context.
struct CodeFileAttachment: Identifiable, Sendable {
    /// The unique identifier of the attachment.
    let id: UUID
    /// The filename of the attachment.
    let filename: String
    /// The programming language of the code.
    let language: SupportedLanguage
    /// The code content.
    let code: String
    /// The size of the code content in bytes.
    let fileSize: Int

    /// Initializes a new `CodeFileAttachment`.
    /// - Parameters:
    ///   - id: The unique identifier.
    ///   - filename: The filename.
    ///   - language: The programming language.
    ///   - code: The code content.
    init(id: UUID = UUID(), filename: String, language: SupportedLanguage, code: String) {
        self.id = id
        self.filename = filename
        self.language = language
        self.code = code
        self.fileSize = code.utf8.count
    }

    /// Returns a human-readable string representation of the file size.
    var formattedSize: String {
        if fileSize < 1024 {
            return "\(fileSize) B"
        } else if fileSize < 1024 * 1024 {
            return String(format: "%.1f KB", Double(fileSize) / 1024)
        } else {
            return String(format: "%.1f MB", Double(fileSize) / (1024 * 1024))
        }
    }
}
