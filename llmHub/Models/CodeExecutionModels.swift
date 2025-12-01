//
//  CodeExecutionModels.swift
//  llmHub
//
//  Created for Code Interpreter feature
//

import Foundation

// MARK: - Supported Languages

enum SupportedLanguage: String, CaseIterable, Codable, Sendable {
    case swift
    case python
    case typescript
    case javascript
    case dart
    
    var displayName: String {
        switch self {
        case .swift: return "Swift"
        case .python: return "Python"
        case .typescript: return "TypeScript"
        case .javascript: return "JavaScript"
        case .dart: return "Dart"
        }
    }
    
    /// Nonisolated accessor for display name (safe for use in error descriptions)
    nonisolated var displayNameValue: String {
        switch self {
        case .swift: return "Swift"
        case .python: return "Python"
        case .typescript: return "TypeScript"
        case .javascript: return "JavaScript"
        case .dart: return "Dart"
        }
    }
    
    var fileExtension: String {
        switch self {
        case .swift: return ".swift"
        case .python: return ".py"
        case .typescript: return ".ts"
        case .javascript: return ".js"
        case .dart: return ".dart"
        }
    }
    
    /// Nonisolated version for use in actors
    nonisolated var fileExtensionValue: String {
        switch self {
        case .swift: return ".swift"
        case .python: return ".py"
        case .typescript: return ".ts"
        case .javascript: return ".js"
        case .dart: return ".dart"
        }
    }
    
    var interpreterName: String {
        switch self {
        case .swift: return "swift"
        case .python: return "python3"
        case .typescript: return "ts-node"
        case .javascript: return "node"
        case .dart: return "dart"
        }
    }
    
    /// Nonisolated accessor for interpreter name (safe for use in error descriptions)
    nonisolated var interpreterNameValue: String {
        switch self {
        case .swift: return "swift"
        case .python: return "python3"
        case .typescript: return "ts-node"
        case .javascript: return "node"
        case .dart: return "dart"
        }
    }
    
    /// Detect language from file extension
    static func from(extension ext: String) -> SupportedLanguage? {
        let normalized = ext.lowercased().hasPrefix(".") ? ext.lowercased() : ".\(ext.lowercased())"
        return allCases.first { $0.fileExtension == normalized }
    }
    
    /// Detect language from filename
    static func from(filename: String) -> SupportedLanguage? {
        let ext = (filename as NSString).pathExtension
        return from(extension: ext)
    }
}

// MARK: - Security Mode

enum CodeSecurityMode: String, CaseIterable, Codable, Sendable {
    case sandbox
    case approval
    case unrestricted
    
    var displayName: String {
        switch self {
        case .sandbox: return "Sandbox"
        case .approval: return "Require Approval"
        case .unrestricted: return "Unrestricted"
        }
    }
    
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
    
    var systemImage: String {
        switch self {
        case .sandbox: return "lock.shield"
        case .approval: return "checkmark.shield"
        case .unrestricted: return "exclamationmark.shield"
        }
    }
}

// MARK: - Execution Result

struct CodeExecutionResult: Codable, Sendable {
    let id: UUID
    let language: SupportedLanguage
    let code: String
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let executionTimeMs: Int
    let timestamp: Date
    let sandboxPath: String?
    
    var isSuccess: Bool {
        exitCode == 0
    }
    
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
    
    /// Format for LLM context
    var llmSummary: String {
        """
        Language: \(language.displayName)
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

struct InterpreterInfo: Sendable {
    let language: SupportedLanguage
    let path: String
    let version: String?
    let isAvailable: Bool
    
    static func unavailable(_ language: SupportedLanguage) -> InterpreterInfo {
        InterpreterInfo(language: language, path: "", version: nil, isAvailable: false)
    }
}

// MARK: - Execution Request

struct CodeExecutionRequest: Sendable {
    let id: UUID
    let language: SupportedLanguage
    let code: String
    let timeoutSeconds: Int
    let workingDirectory: URL?
    
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

enum CodeExecutionError: LocalizedError, Sendable {
    case interpreterNotFound(SupportedLanguage)
    case timeout(seconds: Int)
    case sandboxCreationFailed(String)
    case fileWriteFailed(String)
    case processLaunchFailed(String)
    case executionCancelled
    case approvalDenied
    
    var errorDescription: String? {
        switch self {
        case .interpreterNotFound(let lang):
            return "Interpreter for \(lang.displayNameValue) not found. Please install \(lang.interpreterNameValue)."
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

struct CodeFileAttachment: Identifiable, Sendable {
    let id: UUID
    let filename: String
    let language: SupportedLanguage
    let code: String
    let fileSize: Int
    
    init(id: UUID = UUID(), filename: String, language: SupportedLanguage, code: String) {
        self.id = id
        self.filename = filename
        self.language = language
        self.code = code
        self.fileSize = code.utf8.count
    }
    
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

