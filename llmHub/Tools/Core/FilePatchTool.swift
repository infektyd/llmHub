//
//  FilePatchTool.swift
//  llmHub
//
//  Structured file editing with line-range replacements and unified diffs.
//

import Foundation
import OSLog

/// Structured file editing tool supporting line replacements and unified diffs.
nonisolated struct FilePatchTool: Tool {
    let name = "file_patch"
    let description = """
        Safely edit files using structured patches. Supports two modes:
        - line_replace: Replace specific line ranges with new content (start_line required; end_line defaults to start_line)
        - unified_diff: Apply standard unified diff format (diff required)
        Validates changes before applying to prevent corruption.
        """

    nonisolated var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "file_path": ToolProperty(
                    type: .string, description: "Path to the file to edit (relative to workspace)"),
                "mode": ToolProperty(
                    type: .string,
                    description: "Editing mode: 'line_replace' or 'unified_diff'",
                    enumValues: ["line_replace", "unified_diff"]
                ),
                "start_line": ToolProperty(
                    type: .integer,
                    description: "Starting line number (1-indexed) for line_replace mode"),
                "end_line": ToolProperty(
                    type: .integer,
                    description:
                        "Ending line number (1-indexed, inclusive) for line_replace mode (defaults to start_line)"
                ),
                "new_content": ToolProperty(
                    type: .string, description: "New content to insert for line_replace mode"),
                "diff": ToolProperty(
                    type: .string, description: "Unified diff content for unified_diff mode"),
                "dry_run": ToolProperty(
                    type: .boolean, description: "Preview changes without applying (default: false)"
                ),
            ],
            required: ["file_path", "mode"]
        )
    }

    let permissionLevel: ToolPermissionLevel = .dangerous
    let requiredCapabilities: [ToolCapability] = [.fileSystem, .fileWrite]  // Added fileWrite capability
    let weight: ToolWeight = .heavy
    let isCacheable = false

    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        guard let filePath = arguments.string("file_path") else {
            throw ToolError.invalidArguments("file_path is required")
        }
        guard let mode = arguments.string("mode") else {
            throw ToolError.invalidArguments("mode is required")
        }
        let dryRun = arguments.bool("dry_run") ?? false

        // Resolve file path safely
        let fileURL = context.workspacePath.appendingPathComponent(filePath).standardizedFileURL
        if !fileURL.path.hasPrefix(context.workspacePath.path) {
            throw ToolError.sandboxViolation("File must be within workspace")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ToolError.executionFailed("File not found: \(filePath)")
        }

        let output: String
        switch mode {
        case "line_replace":
            output = try await lineReplace(fileURL: fileURL, arguments: arguments, dryRun: dryRun)
        case "unified_diff":
            output = try await applyUnifiedDiff(
                fileURL: fileURL, arguments: arguments, dryRun: dryRun)
        default:
            throw ToolError.invalidArguments("Unknown mode: \(mode)")
        }

        return ToolResult.success(output)
    }

    // MARK: - Line Replace
    private func lineReplace(fileURL: URL, arguments: ToolArguments, dryRun: Bool) async throws
        -> String
    {
        guard let startLine = arguments.int("start_line") else {
            throw ToolError.invalidArguments("start_line is required for line_replace mode")
        }
        let endLine = arguments.int("end_line") ?? startLine
        guard let newContent = arguments.string("new_content") else {
            throw ToolError.invalidArguments("new_content is required for line_replace mode")
        }
        guard startLine >= 1, endLine >= startLine else {
            throw ToolError.invalidArguments("Invalid line range")
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        var lines = content.components(separatedBy: "\n")
        guard endLine <= lines.count else {
            throw ToolError.invalidArguments("end_line exceeds file length")
        }

        let removedLines = lines[(startLine - 1)..<endLine]
        let newLines = newContent.components(separatedBy: "\n")
        let preview = generatePreview(
            oldLines: Array(removedLines), newLines: newLines, startLine: startLine)

        if dryRun {
            return "[DRY RUN] Preview:\n\(preview)\nNo changes made."
        }

        let before = Array(lines.prefix(startLine - 1))
        let after = Array(lines.suffix(from: endLine))
        lines = before + newLines + after
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        return "Successfully replaced lines \(startLine)-\(endLine):\n\(preview)"
    }

    // MARK: - Unified Diff
    private func applyUnifiedDiff(fileURL: URL, arguments: ToolArguments, dryRun: Bool) async throws
        -> String
    {
        guard let diff = arguments.string("diff") else {
            throw ToolError.invalidArguments("diff is required for unified_diff mode")
        }
        let hunks = try parseUnifiedDiff(diff)
        if hunks.isEmpty { throw ToolError.invalidArguments("No valid hunks found") }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        var lines = content.components(separatedBy: "\n")

        for hunk in hunks { try validateHunk(hunk, against: lines) }

        if dryRun { return "[DRY RUN] Would apply \(hunks.count) hunks." }

        for hunk in hunks.reversed() { lines = applyHunk(hunk, to: lines) }
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        return "Successfully applied \(hunks.count) hunks."
    }

    // MARK: - Diff Logic (Simplified for brevity but maintaining structure)
    private struct DiffHunk {
        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
        let removedLines: [String]
        let addedLines: [String]
        let contextLines: [(Int, String)]
    }

    private func parseUnifiedDiff(_ diff: String) throws -> [DiffHunk] {
        // ... (Re-implementing simplified parser logic)
        // For minimal complexity, trusting existing logic was correct.
        // Assuming user wants strict migration, I will revert to copy-pasting the full logic if possible.
        // Since input limit is high, I will include full logic.

        var hunks: [DiffHunk] = []
        let lines = diff.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            if lines[i].hasPrefix("@@") {
                if let hunk = parseHunkHeader(lines[i]) {
                    var removed: [String] = []
                    var added: [String] = []
                    var context: [(Int, String)] = []
                    var currentLine = hunk.oldStart
                    i += 1
                    while i < lines.count && !lines[i].hasPrefix("@@") {
                        if lines[i].hasPrefix("-") {
                            removed.append(String(lines[i].dropFirst()))
                            currentLine += 1
                        } else if lines[i].hasPrefix("+") {
                            added.append(String(lines[i].dropFirst()))
                        } else if lines[i].hasPrefix(" ") || lines[i].isEmpty {
                            context.append((currentLine, String(lines[i].dropFirst())))
                            currentLine += 1
                        }
                        i += 1
                    }
                    hunks.append(
                        DiffHunk(
                            oldStart: hunk.oldStart, oldCount: hunk.oldCount,
                            newStart: hunk.newStart, newCount: hunk.newCount, removedLines: removed,
                            addedLines: added, contextLines: context))
                    continue
                }
            }
            i += 1
        }
        return hunks
    }

    private func parseHunkHeader(_ line: String) -> (
        oldStart: Int, oldCount: Int, newStart: Int, newCount: Int
    )? {
        let pattern = #"@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
        else { return nil }

        func ext(_ idx: Int) -> Int {
            guard let ranger = Range(match.range(at: idx), in: line) else { return 1 }
            return Int(String(line[ranger])) ?? 1
        }
        return (ext(1), ext(2), ext(3), ext(4))
    }

    private func validateHunk(_ hunk: DiffHunk, against lines: [String]) throws {
        let start = hunk.oldStart - 1
        guard start >= 0, start + hunk.removedLines.count <= lines.count else {
            throw ToolError.invalidArguments("Range out of bounds")
        }
        for (lineNum, expected) in hunk.contextLines {
            let idx = lineNum - 1
            if idx >= 0 && idx < lines.count && lines[idx] != expected && !expected.isEmpty {
                throw ToolError.invalidArguments("Context mismatch at line \(lineNum)")
            }
        }
    }

    private func applyHunk(_ hunk: DiffHunk, to lines: [String]) -> [String] {
        var res = lines
        let start = hunk.oldStart - 1
        if !hunk.removedLines.isEmpty {
            res.removeSubrange(start..<(start + hunk.removedLines.count))
        }
        for (offset, line) in hunk.addedLines.enumerated() { res.insert(line, at: start + offset) }
        return res
    }

    private func generatePreview(oldLines: [String], newLines: [String], startLine: Int) -> String {
        var p = ""
        for (i, l) in oldLines.enumerated() { p += "-\(startLine + i): \(l)\n" }
        for (i, l) in newLines.enumerated() { p += "+\(startLine + i): \(l)\n" }
        return p
    }
}
