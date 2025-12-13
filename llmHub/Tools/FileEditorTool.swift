//
//  FileEditorTool.swift
//  llmHub
//
//  File editing tool with create, edit, append, delete, rename, move, copy operations
//

import Foundation
import OSLog

/// File Editor Tool conforming to the unified Tool protocol.
nonisolated final class FileEditorTool: Tool {
    let name = "file_editor"
    let description = """
        Create, edit, and manage files. Supports creating new files, \
        editing existing files with search/replace, appending content, \
        deleting, renaming, moving, and copying files.
        """

    var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "operation": ToolProperty(
                    type: .string,
                    description: "The operation to perform",
                    enumValues: ["create", "edit", "append", "delete", "rename", "move", "copy"]
                ),
                "path": ToolProperty(
                    type: .string, description: "The target file path (absolute or relative)"),
                "content": ToolProperty(
                    type: .string, description: "Content to write (for create/append operations)"),
                "old_string": ToolProperty(
                    type: .string, description: "Text to find and replace (for edit operation)"),
                "new_string": ToolProperty(
                    type: .string, description: "Replacement text (for edit operation)"),
                "destination": ToolProperty(
                    type: .string, description: "Destination path (for rename/move/copy operations)"
                ),
            ],
            required: ["operation", "path"]
        )
    }

    let permissionLevel: ToolPermissionLevel = .dangerous
    let requiredCapabilities: [ToolCapability] = [.fileSystem, .fileWrite]
    let weight: ToolWeight = .heavy
    let isCacheable = false

    init() {}

    func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        guard let operationStr = arguments.string("operation") else {
            throw ToolError.invalidArguments("operation is required")
        }
        guard let path = arguments.string("path") else {
            throw ToolError.invalidArguments("path is required")
        }

        let fileURL = context.workspacePath.appendingPathComponent(path).standardizedFileURL
        if !fileURL.path.hasPrefix(context.workspacePath.path) {
            throw ToolError.sandboxViolation("File must be within workspace")
        }

        let operations: [String] = ["create", "edit", "append", "delete", "rename", "move", "copy"]
        guard operations.contains(operationStr) else {
            throw ToolError.invalidArguments("Unknown operation")
        }

        let fm = FileManager.default

        switch operationStr {
        case "create":
            guard let content = arguments.string("content") else {
                throw ToolError.invalidArguments("content required")
            }
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return ToolResult.success("File created at \(path)")

        case "edit":
            guard let oldStr = arguments.string("old_string"),
                let newStr = arguments.string("new_string")
            else {
                throw ToolError.invalidArguments("old_string and new_string required")
            }
            guard fm.fileExists(atPath: fileURL.path) else {
                throw ToolError.executionFailed("File not found")
            }
            let original = try String(contentsOf: fileURL, encoding: .utf8)
            guard original.contains(oldStr) else {
                throw ToolError.executionFailed("old_string not found")
            }
            let newContent = original.replacingOccurrences(of: oldStr, with: newStr)
            try newContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return ToolResult.success("File edited")

        case "append":
            guard let content = arguments.string("content") else {
                throw ToolError.invalidArguments("content required")
            }
            guard fm.fileExists(atPath: fileURL.path) else {
                throw ToolError.executionFailed("File not found")
            }
            let original = try String(contentsOf: fileURL, encoding: .utf8)
            try (original + content).write(to: fileURL, atomically: true, encoding: .utf8)
            return ToolResult.success("Content appended")

        case "delete":
            try fm.removeItem(at: fileURL)
            return ToolResult.success("File deleted")

        case "rename", "move":
            guard let dest = arguments.string("destination") else {
                throw ToolError.invalidArguments("destination required")
            }
            let destURL = context.workspacePath.appendingPathComponent(dest).standardizedFileURL
            try fm.moveItem(at: fileURL, to: destURL)
            return ToolResult.success("Moved to \(dest)")

        case "copy":
            guard let dest = arguments.string("destination") else {
                throw ToolError.invalidArguments("destination required")
            }
            let destURL = context.workspacePath.appendingPathComponent(dest).standardizedFileURL
            try fm.copyItem(at: fileURL, to: destURL)
            return ToolResult.success("Copied to \(dest)")

        default:
            throw ToolError.invalidArguments("Operation not implemented")
        }
    }
}
