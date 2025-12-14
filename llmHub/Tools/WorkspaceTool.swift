//
//  WorkspaceTool.swift
//  llmHub
//
//  Project introspection tool for file listing and text search.
//

import Foundation
import OSLog

/// Project introspection tool supporting file listing and text search.
nonisolated struct WorkspaceTool: Tool {
    let name = "workspace"
    let description = """
        Inspect the project workspace. Supports two operations:
        - list_files: Recursively list files with .gitignore support
        - grep: Search for text patterns in files
        Use this to understand project structure and find specific code.
        """

    nonisolated var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "operation": ToolProperty(
                    type: .string,
                    description: "Operation to perform: 'list_files' or 'grep'",
                    enumValues: ["list_files", "grep"]
                ),
                "path": ToolProperty(
                    type: .string, description: "Relative path within workspace (default: root)"),
                "pattern": ToolProperty(
                    type: .string, description: "Search pattern for grep operation"),
                "max_depth": ToolProperty(
                    type: .integer,
                    description: "Maximum directory depth for list_files (default: 5)"),
                "include_hidden": ToolProperty(
                    type: .boolean, description: "Include hidden files/directories (default: false)"
                ),
                "file_extensions": ToolProperty(
                    type: .array,
                    description: "Filter by file extensions (e.g., ['swift', 'py'])",
                    items: ToolProperty(type: .string, description: "File extension")
                ),
            ],
            required: ["operation"]
        )
    }

    let permissionLevel: ToolPermissionLevel = .sensitive
    let requiredCapabilities: [ToolCapability] = [.fileSystem]
    let weight: ToolWeight = .fast
    let isCacheable = false

    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        guard let operation = arguments.string("operation") else {
            throw ToolError.invalidArguments("operation is required")
        }
        let relativePath = arguments.string("path") ?? "."
        let targetURL = context.workspacePath.appendingPathComponent(relativePath)
            .standardizedFileURL

        if !targetURL.path.hasPrefix(context.workspacePath.path) {
            throw ToolError.sandboxViolation("Path must be within workspace")
        }

        switch operation {
        case "list_files":
            let output = try await listFiles(at: targetURL, arguments: arguments, context: context)
            return ToolResult.success(output)
        case "grep":
            let output = try await grepSearch(at: targetURL, arguments: arguments, context: context)
            return ToolResult.success(output)
        default:
            throw ToolError.invalidArguments("Unknown operation: \(operation)")
        }
    }

    private func listFiles(at url: URL, arguments: ToolArguments, context: ToolContext) async throws
        -> String
    {
        let maxDepth = arguments.int("max_depth") ?? 5
        let includeHidden = arguments.bool("include_hidden") ?? false
        var extFilter: Set<String>?
        if let exts = arguments.array("file_extensions") {
            extFilter = Set(exts.compactMap { $0.stringValue?.lowercased() })
        }

        let gitignorePatterns = loadGitignorePatterns(in: context.workspacePath)
        var results: [String] = []
        var fileCount = 0
        var dirCount = 0
        let maxResults = 500

        let fm = FileManager.default
        let enumerator = fm.enumerator(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: includeHidden ? [] : [.skipsHiddenFiles])

        while let itemURL = enumerator?.nextObject() as? URL {
            let relativePath = itemURL.path.replacingOccurrences(of: url.path + "/", with: "")
            if relativePath.components(separatedBy: "/").count > maxDepth {
                enumerator?.skipDescendants()
                continue
            }

            if shouldIgnore(path: relativePath, patterns: gitignorePatterns) {
                if (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator?.skipDescendants()
                }
                continue
            }

            let isDir =
                (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDir, let filter = extFilter, !filter.contains(itemURL.pathExtension.lowercased())
            {
                continue
            }

            if isDir {
                dirCount += 1
                results.append("📁 \(relativePath)/")
            } else {
                fileCount += 1
                let size = (try? itemURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                results.append("📄 \(relativePath) (\(size) B)")
            }

            if results.count >= maxResults {
                results.append("... (truncated)")
                break
            }
        }

        return
            "Workspace: \(url.lastPathComponent)\nFiles: \(fileCount), Directories: \(dirCount)\n\n\(results.joined(separator: "\n"))"
    }

    private func grepSearch(at url: URL, arguments: ToolArguments, context: ToolContext)
        async throws -> String
    {
        guard let pattern = arguments.string("pattern"), !pattern.isEmpty else {
            throw ToolError.invalidArguments("pattern is required")
        }
        #if os(macOS)
            return try await systemGrep(pattern: pattern, at: url)
        #else
            return "Grep not supported on iOS (yet)"
        #endif
    }

    #if os(macOS)
        private func systemGrep(pattern: String, at url: URL) async throws -> String {
            let process = Process()
            process.launchPath = "/usr/bin/grep"
            process.arguments = [
                "-rn", "--include=*.swift", "--include=*.py", "--include=*.js", "--include=*.json",
                "--include=*.md", pattern,
            ]
            process.currentDirectoryURL = url
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.isEmpty ? "No matches." : "Found matches:\n\(output.prefix(5000))"
        }
    #endif

    private func loadGitignorePatterns(in directory: URL) -> [String] {
        guard
            let content = try? String(
                contentsOf: directory.appendingPathComponent(".gitignore"), encoding: .utf8)
        else { return [] }
        return content.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private func shouldIgnore(path: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if pattern.hasSuffix("/") {
                let dir = String(pattern.dropLast())
                if path.hasPrefix(dir) || path.contains("/\(dir)/") { return true }
            } else if pattern.hasPrefix("*") {
                if path.hasSuffix(String(pattern.dropFirst())) { return true }
            } else if path.contains(pattern) {
                return true
            }
        }
        return false
    }
}
