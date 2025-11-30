//
//  FileOperationModels.swift
//  llmHub
//
//  Models for file editing operations
//

import Foundation

// MARK: - File Operation Types

/// Types of file operations the editor can perform
enum FileOperation: String, CaseIterable, Codable, Sendable {
    case create     // Create a new file
    case edit       // Search and replace within a file
    case append     // Append content to end of file
    case delete     // Delete a file
    case rename     // Rename a file
    case move       // Move a file to a different location
    case copy       // Copy a file
    
    var displayName: String {
        switch self {
        case .create: return "Create"
        case .edit: return "Edit"
        case .append: return "Append"
        case .delete: return "Delete"
        case .rename: return "Rename"
        case .move: return "Move"
        case .copy: return "Copy"
        }
    }
    
    var systemImage: String {
        switch self {
        case .create: return "doc.badge.plus"
        case .edit: return "pencil"
        case .append: return "text.append"
        case .delete: return "trash"
        case .rename: return "pencil.line"
        case .move: return "folder"
        case .copy: return "doc.on.doc"
        }
    }
    
    var requiresContent: Bool {
        switch self {
        case .create, .append: return true
        case .edit, .delete, .rename, .move, .copy: return false
        }
    }
    
    var requiresDestination: Bool {
        switch self {
        case .rename, .move, .copy: return true
        case .create, .edit, .append, .delete: return false
        }
    }
}

// MARK: - Security Mode

/// Security mode for file operations
enum FileSecurityMode: String, CaseIterable, Codable, Sendable {
    case approval      // Require user approval before each operation
    case unrestricted  // Execute immediately without confirmation
    
    var displayName: String {
        switch self {
        case .approval: return "Require Approval"
        case .unrestricted: return "Unrestricted"
        }
    }
    
    var description: String {
        switch self {
        case .approval:
            return "Shows a diff preview and requires user confirmation before each file operation"
        case .unrestricted:
            return "Executes file operations immediately without confirmation (power user mode)"
        }
    }
    
    var systemImage: String {
        switch self {
        case .approval: return "checkmark.shield"
        case .unrestricted: return "exclamationmark.shield"
        }
    }
}

// MARK: - Operation Request

/// Request for a file operation
struct FileOperationRequest: Sendable {
    let id: UUID
    let operation: FileOperation
    let path: String
    let content: String?
    let oldString: String?
    let newString: String?
    let destination: String?
    let timestamp: Date
    
    init(
        id: UUID = UUID(),
        operation: FileOperation,
        path: String,
        content: String? = nil,
        oldString: String? = nil,
        newString: String? = nil,
        destination: String? = nil
    ) {
        self.id = id
        self.operation = operation
        self.path = path
        self.content = content
        self.oldString = oldString
        self.newString = newString
        self.destination = destination
        self.timestamp = Date()
    }
    
    /// Resolve the file path to an absolute URL
    var resolvedURL: URL {
        let expandedPath = (path as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath)
        } else {
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(path)
        }
    }
    
    /// Resolve the destination path to an absolute URL
    var resolvedDestinationURL: URL? {
        guard let dest = destination else { return nil }
        let expandedPath = (dest as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath)
        } else {
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(dest)
        }
    }
}

// MARK: - Operation Result

/// Result of a file operation
struct FileOperationResult: Codable, Sendable {
    let id: UUID
    let operation: FileOperation
    let path: String
    let success: Bool
    let message: String
    let bytesWritten: Int?
    let timestamp: Date
    
    /// Format for LLM context
    var llmSummary: String {
        if success {
            var summary = "✅ \(operation.displayName) succeeded: \(path)"
            if let bytes = bytesWritten, bytes > 0 {
                summary += " (\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)))"
            }
            return summary
        } else {
            return "❌ \(operation.displayName) failed: \(message)"
        }
    }
}

// MARK: - Diff Preview

/// Preview of changes for approval
struct FileOperationPreview: Sendable {
    let request: FileOperationRequest
    let originalContent: String?
    let proposedContent: String?
    let diffLines: [DiffLine]
    
    /// Generate a text diff for display
    var textDiff: String {
        guard originalContent != nil, proposedContent != nil else {
            if let proposed = proposedContent {
                return "New file:\n\(proposed)"
            }
            return "File will be deleted"
        }
        
        var diff = ""
        for line in diffLines {
            switch line.type {
            case .unchanged:
                diff += "  \(line.content)\n"
            case .removed:
                diff += "- \(line.content)\n"
            case .added:
                diff += "+ \(line.content)\n"
            }
        }
        return diff
    }
}

/// A single line in a diff
struct DiffLine: Sendable {
    enum LineType {
        case unchanged
        case removed
        case added
    }
    
    let type: LineType
    let content: String
    let lineNumber: Int?
}

// MARK: - Errors

/// Errors that can occur during file operations
enum FileOperationError: LocalizedError, Sendable {
    case fileNotFound(String)
    case fileAlreadyExists(String)
    case accessDenied(String)
    case invalidOperation(String)
    case searchStringNotFound(String)
    case writeFailed(String)
    case operationDenied
    case invalidPath(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileAlreadyExists(let path):
            return "File already exists: \(path)"
        case .accessDenied(let path):
            return "Access denied: \(path)"
        case .invalidOperation(let reason):
            return "Invalid operation: \(reason)"
        case .searchStringNotFound(let str):
            return "Search string not found: \"\(str)\""
        case .writeFailed(let reason):
            return "Write failed: \(reason)"
        case .operationDenied:
            return "Operation denied by user"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        }
    }
}

// MARK: - Operation History

/// Tracks file operations for potential undo
struct FileOperationHistoryEntry: Codable, Sendable {
    let id: UUID
    let operation: FileOperation
    let path: String
    let originalContent: String?
    let newContent: String?
    let destination: String?
    let timestamp: Date
    let canUndo: Bool
}

