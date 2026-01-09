//
//  FileOperationModels.swift
//  llmHub
//
//  Models for file editing operations
//

import Foundation

// MARK: - File Operation Types

/// Types of file operations the editor can perform.
enum FileOperation: String, CaseIterable, Codable, Sendable {
    /// Create a new file.
    case create
    /// Search and replace text within a file.
    case edit
    /// Append content to the end of a file.
    case append
    /// Delete a file.
    case delete
    /// Rename a file.
    case rename
    /// Move a file to a different location.
    case move
    /// Copy a file.
    case copy

    /// The display name of the operation.
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

    /// The system image name for the operation's icon.
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

    /// Indicates if the operation requires content input.
    var requiresContent: Bool {
        switch self {
        case .create, .append: return true
        case .edit, .delete, .rename, .move, .copy: return false
        }
    }

    /// Indicates if the operation requires a destination path.
    var requiresDestination: Bool {
        switch self {
        case .rename, .move, .copy: return true
        case .create, .edit, .append, .delete: return false
        }
    }
}

// MARK: - Security Mode

/// Security mode for file operations.
enum FileSecurityMode: String, CaseIterable, Codable, Sendable {
    /// Require user approval before each operation.
    case approval
    /// Execute immediately without confirmation.
    case unrestricted

    /// The display name of the security mode.
    var displayName: String {
        switch self {
        case .approval: return "Require Approval"
        case .unrestricted: return "Unrestricted"
        }
    }

    /// A description of the security mode.
    var description: String {
        switch self {
        case .approval:
            return "Shows a diff preview and requires user confirmation before each file operation"
        case .unrestricted:
            return "Executes file operations immediately without confirmation (power user mode)"
        }
    }

    /// The system image name for the security mode icon.
    var systemImage: String {
        switch self {
        case .approval: return "checkmark.shield"
        case .unrestricted: return "exclamationmark.shield"
        }
    }
}

// MARK: - Operation Request

/// Request for a file operation.
struct FileOperationRequest: Sendable {
    /// The unique identifier of the request.
    let id: UUID
    /// The type of file operation.
    let operation: FileOperation
    /// The path to the file.
    let path: String
    /// The content associated with the operation (e.g., new file content).
    let content: String?
    /// The string to replace in an edit operation.
    let oldString: String?
    /// The string to replace with in an edit operation.
    let newString: String?
    /// The destination path for move/copy/rename operations.
    let destination: String?
    /// The timestamp of the request.
    let timestamp: Date

    /// Initializes a new `FileOperationRequest`.
    /// - Parameters:
    ///   - id: The unique identifier (default: UUID()).
    ///   - operation: The type of operation.
    ///   - path: The file path.
    ///   - content: The content (optional).
    ///   - oldString: The string to replace (optional).
    ///   - newString: The replacement string (optional).
    ///   - destination: The destination path (optional).
    nonisolated init(
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

    /// Resolves the file path to an absolute URL.
    var resolvedURL: URL {
        let expandedPath = (path as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath)
        } else {
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(path)
        }
    }

    /// Resolves the destination path to an absolute URL, if applicable.
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

/// Result of a file operation.
struct FileOperationResult: Codable, Sendable {
    /// The unique identifier of the operation.
    let id: UUID
    /// The type of operation performed.
    let operation: FileOperation
    /// The path of the affected file.
    let path: String
    /// Indicates if the operation was successful.
    let success: Bool
    /// A message describing the outcome.
    let message: String
    /// The number of bytes written, if applicable.
    let bytesWritten: Int?
    /// The timestamp of the result.
    let timestamp: Date

    /// Formats the result for inclusion in LLM context.
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

/// Preview of changes for user approval.
struct FileOperationPreview: Sendable {
    /// The original request causing the change.
    let request: FileOperationRequest
    /// The original content of the file.
    let originalContent: String?
    /// The proposed content after the operation.
    let proposedContent: String?
    /// A list of diff lines showing the changes.
    let diffLines: [DiffLine]

    /// Generates a text representation of the diff for display.
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

/// Represents a single line in a diff.
struct DiffLine: Sendable {
    /// The type of change for the line.
    enum LineType {
        /// The line is unchanged.
        case unchanged
        /// The line was removed.
        case removed
        /// The line was added.
        case added
    }

    /// The type of the line change.
    let type: LineType
    /// The content of the line.
    let content: String
    /// The line number in the original file, if applicable.
    let lineNumber: Int?
}

// MARK: - Errors

/// Errors that can occur during file operations.
enum FileOperationError: LocalizedError, Sendable {
    /// The file was not found.
    case fileNotFound(String)
    /// The file already exists.
    case fileAlreadyExists(String)
    /// Access to the file was denied.
    case accessDenied(String)
    /// The operation is invalid.
    case invalidOperation(String)
    /// The search string for an edit was not found.
    case searchStringNotFound(String)
    /// Writing to the file failed.
    case writeFailed(String)
    /// The operation was denied by the user.
    case operationDenied
    /// The path is invalid.
    case invalidPath(String)

    /// A localized description of the error.
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

/// Tracks file operations for potential undo functionality.
struct FileOperationHistoryEntry: Codable, Sendable {
    /// The unique identifier of the entry.
    let id: UUID
    /// The type of operation performed.
    let operation: FileOperation
    /// The path of the affected file.
    let path: String
    /// The original content of the file before the operation.
    let originalContent: String?
    /// The new content of the file after the operation.
    let newContent: String?
    /// The destination path for move/copy/rename operations.
    let destination: String?
    /// The timestamp of the operation.
    let timestamp: Date
    /// Indicates if the operation can be undone.
    let canUndo: Bool
}
