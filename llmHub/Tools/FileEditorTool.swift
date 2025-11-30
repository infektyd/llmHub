//
//  FileEditorTool.swift
//  llmHub
//
//  File editing tool with create, edit, append, delete, rename, move, copy operations
//  Supports approval and unrestricted security modes
//

import Foundation
import OSLog

/// File Editor Tool conforming to the Tool protocol
/// Provides comprehensive file manipulation capabilities with configurable security
final class FileEditorTool: Tool, @unchecked Sendable {
    let id = "file_editor"
    let name = "file_editor"
    let description = """
        Create, edit, and manage files. Supports creating new files, \
        editing existing files with search/replace, appending content, \
        deleting, renaming, moving, and copying files. \
        Use this when you need to write or modify files.
        """
    
    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "operation": [
                    "type": "string",
                    "enum": FileOperation.allCases.map { $0.rawValue },
                    "description": "The operation to perform: create, edit, append, delete, rename, move, or copy"
                ],
                "path": [
                    "type": "string",
                    "description": "The target file path (absolute or relative)"
                ],
                "content": [
                    "type": "string",
                    "description": "Content to write (for create/append operations)"
                ],
                "old_string": [
                    "type": "string",
                    "description": "Text to find and replace (for edit operation)"
                ],
                "new_string": [
                    "type": "string",
                    "description": "Replacement text (for edit operation)"
                ],
                "destination": [
                    "type": "string",
                    "description": "Destination path (for rename/move/copy operations)"
                ]
            ],
            "required": ["operation", "path"]
        ]
    }
    
    private let logger = Logger(subsystem: "com.llmhub", category: "FileEditorTool")
    
    // Configuration
    var securityMode: FileSecurityMode = .approval
    
    // Approval callback for UI integration
    var approvalHandler: ((FileOperationPreview) async -> Bool)?
    
    // Event callbacks for UI updates
    var onOperationStart: ((FileOperationRequest) -> Void)?
    var onOperationComplete: ((FileOperationResult) -> Void)?
    
    // Operation history for undo capability
    private var history: [FileOperationHistoryEntry] = []
    private let historyLimit = 50
    
    // MARK: - Tool Protocol
    
    func execute(input: [String: Any]) async throws -> String {
        guard let operationStr = input["operation"] as? String,
              let operation = FileOperation(rawValue: operationStr) else {
            throw ToolError.invalidInput
        }
        
        guard let path = input["path"] as? String, !path.isEmpty else {
            throw ToolError.invalidInput
        }
        
        let request = FileOperationRequest(
            operation: operation,
            path: path,
            content: input["content"] as? String,
            oldString: input["old_string"] as? String,
            newString: input["new_string"] as? String,
            destination: input["destination"] as? String
        )
        
        return try await executeOperation(request)
    }
    
    // MARK: - Operation Execution
    
    /// Execute a file operation with security checks
    func executeOperation(_ request: FileOperationRequest) async throws -> String {
        logger.info("Executing \(request.operation.rawValue) on \(request.path)")
        
        // Notify start
        onOperationStart?(request)
        
        // Validate the request
        try validateRequest(request)
        
        // In approval mode, show preview and wait for confirmation
        if securityMode == .approval {
            let preview = try generatePreview(for: request)
            
            guard let handler = approvalHandler else {
                throw FileOperationError.operationDenied
            }
            
            let approved = await handler(preview)
            if !approved {
                let result = FileOperationResult(
                    id: request.id,
                    operation: request.operation,
                    path: request.path,
                    success: false,
                    message: "Operation cancelled by user",
                    bytesWritten: nil,
                    timestamp: Date()
                )
                onOperationComplete?(result)
                throw FileOperationError.operationDenied
            }
        }
        
        // Execute the operation
        let result: FileOperationResult
        
        do {
            switch request.operation {
            case .create:
                result = try performCreate(request)
            case .edit:
                result = try performEdit(request)
            case .append:
                result = try performAppend(request)
            case .delete:
                result = try performDelete(request)
            case .rename:
                result = try performRename(request)
            case .move:
                result = try performMove(request)
            case .copy:
                result = try performCopy(request)
            }
        } catch {
            let failResult = FileOperationResult(
                id: request.id,
                operation: request.operation,
                path: request.path,
                success: false,
                message: error.localizedDescription,
                bytesWritten: nil,
                timestamp: Date()
            )
            onOperationComplete?(failResult)
            throw error
        }
        
        // Notify completion
        onOperationComplete?(result)
        
        logger.info("Operation completed: \(result.success ? "success" : "failed")")
        
        return result.llmSummary
    }
    
    // MARK: - Validation
    
    private func validateRequest(_ request: FileOperationRequest) throws {
        let fm = FileManager.default
        let url = request.resolvedURL
        
        switch request.operation {
        case .create:
            guard request.content != nil else {
                throw FileOperationError.invalidOperation("Create requires content")
            }
            // Allow creating new files (don't check if exists - will overwrite)
            
        case .edit:
            guard fm.fileExists(atPath: url.path) else {
                throw FileOperationError.fileNotFound(request.path)
            }
            guard request.oldString != nil, request.newString != nil else {
                throw FileOperationError.invalidOperation("Edit requires old_string and new_string")
            }
            
        case .append:
            guard request.content != nil else {
                throw FileOperationError.invalidOperation("Append requires content")
            }
            // File must exist for append
            guard fm.fileExists(atPath: url.path) else {
                throw FileOperationError.fileNotFound(request.path)
            }
            
        case .delete:
            guard fm.fileExists(atPath: url.path) else {
                throw FileOperationError.fileNotFound(request.path)
            }
            
        case .rename, .move, .copy:
            guard fm.fileExists(atPath: url.path) else {
                throw FileOperationError.fileNotFound(request.path)
            }
            guard request.destination != nil else {
                throw FileOperationError.invalidOperation("\(request.operation.rawValue) requires destination")
            }
        }
    }
    
    // MARK: - Preview Generation
    
    private func generatePreview(for request: FileOperationRequest) throws -> FileOperationPreview {
        let fm = FileManager.default
        let url = request.resolvedURL
        
        var originalContent: String? = nil
        var proposedContent: String? = nil
        var diffLines: [DiffLine] = []
        
        switch request.operation {
        case .create:
            proposedContent = request.content
            diffLines = (request.content ?? "").components(separatedBy: .newlines)
                .enumerated()
                .map { DiffLine(type: .added, content: $0.element, lineNumber: $0.offset + 1) }
            
        case .edit:
            if fm.fileExists(atPath: url.path) {
                originalContent = try String(contentsOf: url, encoding: .utf8)
                if let oldStr = request.oldString, let newStr = request.newString {
                    proposedContent = originalContent?.replacingOccurrences(of: oldStr, with: newStr)
                    diffLines = generateDiff(original: originalContent ?? "", proposed: proposedContent ?? "")
                }
            }
            
        case .append:
            if fm.fileExists(atPath: url.path) {
                originalContent = try String(contentsOf: url, encoding: .utf8)
                proposedContent = (originalContent ?? "") + (request.content ?? "")
                
                // Only show the appended lines as additions
                let appendedLines = (request.content ?? "").components(separatedBy: .newlines)
                let startLine = (originalContent ?? "").components(separatedBy: .newlines).count
                diffLines = appendedLines.enumerated()
                    .map { DiffLine(type: .added, content: $0.element, lineNumber: startLine + $0.offset + 1) }
            }
            
        case .delete:
            if fm.fileExists(atPath: url.path) {
                originalContent = try String(contentsOf: url, encoding: .utf8)
                diffLines = (originalContent ?? "").components(separatedBy: .newlines)
                    .enumerated()
                    .map { DiffLine(type: .removed, content: $0.element, lineNumber: $0.offset + 1) }
            }
            
        case .rename, .move, .copy:
            // For file operations, just show the operation description
            let actionVerb = request.operation == .copy ? "Copy" : "Move"
            diffLines = [
                DiffLine(type: .unchanged, content: "\(actionVerb): \(request.path)", lineNumber: nil),
                DiffLine(type: .unchanged, content: "To: \(request.destination ?? "?")", lineNumber: nil)
            ]
        }
        
        return FileOperationPreview(
            request: request,
            originalContent: originalContent,
            proposedContent: proposedContent,
            diffLines: diffLines
        )
    }
    
    private func generateDiff(original: String, proposed: String) -> [DiffLine] {
        let originalLines = original.components(separatedBy: .newlines)
        let proposedLines = proposed.components(separatedBy: .newlines)
        
        var diffLines: [DiffLine] = []
        var i = 0, j = 0
        
        // Simple line-by-line diff (for a proper diff, consider using a library)
        while i < originalLines.count || j < proposedLines.count {
            if i >= originalLines.count {
                // Remaining lines are additions
                diffLines.append(DiffLine(type: .added, content: proposedLines[j], lineNumber: j + 1))
                j += 1
            } else if j >= proposedLines.count {
                // Remaining lines are deletions
                diffLines.append(DiffLine(type: .removed, content: originalLines[i], lineNumber: i + 1))
                i += 1
            } else if originalLines[i] == proposedLines[j] {
                // Lines match
                diffLines.append(DiffLine(type: .unchanged, content: originalLines[i], lineNumber: i + 1))
                i += 1
                j += 1
            } else {
                // Lines differ - show removal then addition
                diffLines.append(DiffLine(type: .removed, content: originalLines[i], lineNumber: i + 1))
                diffLines.append(DiffLine(type: .added, content: proposedLines[j], lineNumber: j + 1))
                i += 1
                j += 1
            }
        }
        
        return diffLines
    }
    
    // MARK: - Operation Implementations
    
    private func performCreate(_ request: FileOperationRequest) throws -> FileOperationResult {
        let url = request.resolvedURL
        let content = request.content ?? ""
        
        // Create parent directories if needed
        let parentDir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        
        // Save original if file exists (for undo)
        var originalContent: String? = nil
        if FileManager.default.fileExists(atPath: url.path) {
            originalContent = try? String(contentsOf: url, encoding: .utf8)
        }
        
        // Write the file
        try content.write(to: url, atomically: true, encoding: .utf8)
        
        // Add to history
        addToHistory(FileOperationHistoryEntry(
            id: request.id,
            operation: .create,
            path: request.path,
            originalContent: originalContent,
            newContent: content,
            destination: nil,
            timestamp: Date(),
            canUndo: true
        ))
        
        return FileOperationResult(
            id: request.id,
            operation: .create,
            path: request.path,
            success: true,
            message: "File created successfully",
            bytesWritten: content.utf8.count,
            timestamp: Date()
        )
    }
    
    private func performEdit(_ request: FileOperationRequest) throws -> FileOperationResult {
        let url = request.resolvedURL
        guard let oldString = request.oldString, let newString = request.newString else {
            throw FileOperationError.invalidOperation("Edit requires old_string and new_string")
        }
        
        // Read original content
        let originalContent = try String(contentsOf: url, encoding: .utf8)
        
        // Check if the search string exists
        guard originalContent.contains(oldString) else {
            throw FileOperationError.searchStringNotFound(oldString)
        }
        
        // Perform replacement
        let newContent = originalContent.replacingOccurrences(of: oldString, with: newString)
        
        // Write back
        try newContent.write(to: url, atomically: true, encoding: .utf8)
        
        // Add to history
        addToHistory(FileOperationHistoryEntry(
            id: request.id,
            operation: .edit,
            path: request.path,
            originalContent: originalContent,
            newContent: newContent,
            destination: nil,
            timestamp: Date(),
            canUndo: true
        ))
        
        let occurrences = originalContent.components(separatedBy: oldString).count - 1
        
        return FileOperationResult(
            id: request.id,
            operation: .edit,
            path: request.path,
            success: true,
            message: "Replaced \(occurrences) occurrence(s)",
            bytesWritten: newContent.utf8.count,
            timestamp: Date()
        )
    }
    
    private func performAppend(_ request: FileOperationRequest) throws -> FileOperationResult {
        let url = request.resolvedURL
        let appendContent = request.content ?? ""
        
        // Read original content
        let originalContent = try String(contentsOf: url, encoding: .utf8)
        let newContent = originalContent + appendContent
        
        // Write back
        try newContent.write(to: url, atomically: true, encoding: .utf8)
        
        // Add to history
        addToHistory(FileOperationHistoryEntry(
            id: request.id,
            operation: .append,
            path: request.path,
            originalContent: originalContent,
            newContent: newContent,
            destination: nil,
            timestamp: Date(),
            canUndo: true
        ))
        
        return FileOperationResult(
            id: request.id,
            operation: .append,
            path: request.path,
            success: true,
            message: "Content appended successfully",
            bytesWritten: appendContent.utf8.count,
            timestamp: Date()
        )
    }
    
    private func performDelete(_ request: FileOperationRequest) throws -> FileOperationResult {
        let url = request.resolvedURL
        
        // Save original content for undo
        let originalContent = try? String(contentsOf: url, encoding: .utf8)
        
        // Delete the file
        try FileManager.default.removeItem(at: url)
        
        // Add to history
        addToHistory(FileOperationHistoryEntry(
            id: request.id,
            operation: .delete,
            path: request.path,
            originalContent: originalContent,
            newContent: nil,
            destination: nil,
            timestamp: Date(),
            canUndo: originalContent != nil
        ))
        
        return FileOperationResult(
            id: request.id,
            operation: .delete,
            path: request.path,
            success: true,
            message: "File deleted successfully",
            bytesWritten: nil,
            timestamp: Date()
        )
    }
    
    private func performRename(_ request: FileOperationRequest) throws -> FileOperationResult {
        let sourceURL = request.resolvedURL
        guard let destURL = request.resolvedDestinationURL else {
            throw FileOperationError.invalidOperation("Rename requires destination")
        }
        
        // Move to new name
        try FileManager.default.moveItem(at: sourceURL, to: destURL)
        
        // Add to history
        addToHistory(FileOperationHistoryEntry(
            id: request.id,
            operation: .rename,
            path: request.path,
            originalContent: nil,
            newContent: nil,
            destination: request.destination,
            timestamp: Date(),
            canUndo: true
        ))
        
        return FileOperationResult(
            id: request.id,
            operation: .rename,
            path: request.path,
            success: true,
            message: "Renamed to \(destURL.lastPathComponent)",
            bytesWritten: nil,
            timestamp: Date()
        )
    }
    
    private func performMove(_ request: FileOperationRequest) throws -> FileOperationResult {
        let sourceURL = request.resolvedURL
        guard let destURL = request.resolvedDestinationURL else {
            throw FileOperationError.invalidOperation("Move requires destination")
        }
        
        // Create destination directory if needed
        let destDir = destURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Move the file
        try FileManager.default.moveItem(at: sourceURL, to: destURL)
        
        // Add to history
        addToHistory(FileOperationHistoryEntry(
            id: request.id,
            operation: .move,
            path: request.path,
            originalContent: nil,
            newContent: nil,
            destination: request.destination,
            timestamp: Date(),
            canUndo: true
        ))
        
        return FileOperationResult(
            id: request.id,
            operation: .move,
            path: request.path,
            success: true,
            message: "Moved to \(destURL.path)",
            bytesWritten: nil,
            timestamp: Date()
        )
    }
    
    private func performCopy(_ request: FileOperationRequest) throws -> FileOperationResult {
        let sourceURL = request.resolvedURL
        guard let destURL = request.resolvedDestinationURL else {
            throw FileOperationError.invalidOperation("Copy requires destination")
        }
        
        // Create destination directory if needed
        let destDir = destURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Copy the file
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        
        // Add to history
        addToHistory(FileOperationHistoryEntry(
            id: request.id,
            operation: .copy,
            path: request.path,
            originalContent: nil,
            newContent: nil,
            destination: request.destination,
            timestamp: Date(),
            canUndo: true
        ))
        
        // Get file size
        let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path)
        let size = attrs?[.size] as? Int
        
        return FileOperationResult(
            id: request.id,
            operation: .copy,
            path: request.path,
            success: true,
            message: "Copied to \(destURL.path)",
            bytesWritten: size,
            timestamp: Date()
        )
    }
    
    // MARK: - History Management
    
    private func addToHistory(_ entry: FileOperationHistoryEntry) {
        history.append(entry)
        
        // Trim history if needed
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }
    
    /// Get operation history
    func getHistory() -> [FileOperationHistoryEntry] {
        history
    }
    
    /// Clear operation history
    func clearHistory() {
        history.removeAll()
    }
}

