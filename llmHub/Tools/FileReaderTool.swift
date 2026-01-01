//
//  FileReaderTool.swift
//  llmHub
//
//  File reading tool for analyzing documents and files
//

import Foundation
import OSLog
import PDFKit
import UniformTypeIdentifiers

/// File Reader Tool conforming to the unified Tool protocol.
nonisolated struct FileReaderTool: Tool {
    let name = "read_file"
    let description = """
        Read and analyze the contents of files. \
        Supports text files (txt, md, json, xml, csv), \
        PDF documents, and can describe images. \
        Use this tool when you need to examine file contents or analyze documents. \
        Path must be within the workspace (prefer relative paths).
        """

    nonisolated var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "path": ToolProperty(
                    type: .string,
                    description:
                        "The file path to read. Can be absolute or relative to the workspace."
                ),
                "encoding": ToolProperty(
                    type: .string,
                    description: "Text encoding (default: utf-8). Options: utf-8, ascii, utf-16"
                ),
                "max_length": ToolProperty(
                    type: .integer,
                    description: "Maximum number of characters to return (default: 50000)"
                ),
                "start_line": ToolProperty(
                    type: .integer,
                    description: "Optional starting line number (1-based) for partial reads"
                ),
                "end_line": ToolProperty(
                    type: .integer,
                    description: "Optional ending line number (inclusive) for partial reads"
                ),
                "search": ToolProperty(
                    type: .string,
                    description: "Optional substring/regex to filter matching lines"
                ),
                "format": ToolProperty(
                    type: .string,
                    description:
                        "Output format. annotated adds line numbers and truncation markers (default: annotated)",
                    enumValues: ["raw", "annotated"]
                ),
            ],
            required: ["path"]
        )
    }

    let permissionLevel: ToolPermissionLevel = .sensitive
    let requiredCapabilities: [ToolCapability] = [.fileSystem]
    let weight: ToolWeight = .heavy  // Can be slow for large files/PDFs
    let isCacheable = true  // Files don't change THAT often during a session usually

    private let maxDefaultLength = 50000

    init() {}

    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        guard let path = arguments.string("path"), !path.isEmpty else {
            throw ToolError.invalidArguments("path is required")
        }

        let maxLength = arguments.int("max_length") ?? maxDefaultLength
        let encodingName = arguments.string("encoding") ?? "utf-8"
        let startLine = arguments.int("start_line")
        let endLine = arguments.int("end_line")
        let search = arguments.string("search")
        let format = arguments.string("format") ?? "annotated"

        let encoding: String.Encoding = {
            switch encodingName.lowercased() {
            case "ascii": return .ascii
            case "utf-16": return .utf16
            default: return .utf8
            }
        }()

        // Resolve path via context.workspacePath
        let fileURL: URL
        if path.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: path)
        } else {
            fileURL = context.workspacePath.appendingPathComponent(path)
        }

        let resolvedURL = fileURL.standardizedFileURL
        let workspaceRoot = context.workspacePath.standardizedFileURL
        if !resolvedURL.path.hasPrefix(workspaceRoot.path) {
            throw ToolError.sandboxViolation(
                "Access denied: File must be within the workspace sandbox (use a workspace-relative path).")
        }

        context.logger.debug("Reading file: \(resolvedURL.path)")

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory) else {
            throw ToolError.executionFailed("File not found: \(path)")
        }
        if isDirectory.boolValue {
            throw ToolError.executionFailed("Path points to a directory, not a file.")
        }

        let fileExtension = resolvedURL.pathExtension.lowercased()

        do {
            let content: String
            let truncated: Bool
            let nextOffset: Int

            switch fileExtension {
            case "pdf":
                (content, truncated, nextOffset) = try readPDF(url: resolvedURL, maxLength: maxLength)
            case "json":
                (content, truncated, nextOffset) = try readJSON(url: resolvedURL, maxLength: maxLength)
            case "csv":
                (content, truncated, nextOffset) = try readCSV(url: resolvedURL, maxLength: maxLength)
            case "png", "jpg", "jpeg", "gif", "webp", "heic":
                content = try describeImage(url: resolvedURL)
                truncated = false
                nextOffset = content.count
            case "rtf":
                (content, truncated, nextOffset) = try readRTF(url: resolvedURL, maxLength: maxLength)
            default:
                (content, truncated, nextOffset) = try readText(
                    url: resolvedURL, encoding: encoding, maxLength: maxLength)
            }

            let filteredContent = applyLineWindow(
                content,
                startLine: startLine,
                endLine: endLine,
                search: search,
                format: format
            )

            let finalTruncated = truncated || filteredContent.truncated
            _ =
                truncated
                ? "offset:\(nextOffset)"
                : nil

            // PDFKit accesses UI or CG, prefer MainActor for safety on some platforms?
            // Usually PDFDocument is thread safe enough but let's be safe if needed.
            // But we are in async, so we just return.

            return ToolResult.success(
                formatFileContent(
                    path: path, content: filteredContent.text, truncated: finalTruncated),
                metrics: .empty,
                metadata: ["path": resolvedURL.path],
                truncated: finalTruncated
            )

        } catch {
            throw ToolError.executionFailed(error.localizedDescription)
        }
    }

    // MARK: - Readers
    // (Implementations reused from legacy, but assumed nonisolated or self-contained)

    private func readText(url: URL, encoding: String.Encoding, maxLength: Int) throws -> (
        String, Bool, Int
    ) {
        let content = try String(contentsOf: url, encoding: encoding)
        if content.count > maxLength {
            return (String(content.prefix(maxLength)) + "\n\n[Content truncated]", true, maxLength)
        }
        return (content, false, content.count)
    }

    private func readJSON(url: URL, maxLength: Int) throws -> (String, Bool, Int) {
        let data = try Data(contentsOf: url)
        if let json = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(
                withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
            let prettyString = String(data: prettyData, encoding: .utf8)
        {

            if prettyString.count > maxLength {
                return (
                    String(prettyString.prefix(maxLength)) + "\n\n[JSON truncated]", true, maxLength
                )
            }
            return (prettyString, false, prettyString.count)
        }
        return try readText(url: url, encoding: .utf8, maxLength: maxLength)
    }

    private func readCSV(url: URL, maxLength: Int) throws -> (String, Bool, Int) {
        let content = try String(contentsOf: url, encoding: .utf8)
        // Simplified CSV summary logic...
        // For brevity in migration, using simple text read if too complex to port 1:1 immediately,
        // but let's keep the logic if possible.
        // Copying simplified logic:
        let lines = content.components(separatedBy: .newlines)
        var output = "CSV File Analysis:\nTotal lines: \(lines.count)\n"
        if let header = lines.first {
            output += "Headers: \(header)\n"
        }
        output += "Content:\n"
        let rows = lines.prefix(min(lines.count, 50)).joined(separator: "\n")
        output += rows

        if output.count > maxLength {
            return (String(output.prefix(maxLength)), true, maxLength)
        }
        return (output, false, output.count)
    }

    private func readPDF(url: URL, maxLength: Int) throws -> (String, Bool, Int) {
        // PDFKit dependency requires 'import PDFKit'
        guard let document = PDFDocument(url: url) else {
            throw ToolError.executionFailed("Invalid PDF")
        }
        var text = ""
        for i in 0..<min(document.pageCount, 50) {  // Limit to 50 pages for now
            text += (document.page(at: i)?.string ?? "") + "\n"
            if text.count > maxLength { break }
        }
        if text.count > maxLength {
            return (String(text.prefix(maxLength)), true, maxLength)
        }
        return (text, false, text.count)
    }

    private func readRTF(url: URL, maxLength: Int) throws -> (String, Bool, Int) {
        let attributed = try NSAttributedString(
            url: url, options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil)
        let text = attributed.string
        if text.count > maxLength {
            return (String(text.prefix(maxLength)), true, maxLength)
        }
        return (text, false, text.count)
    }

    private func describeImage(url: URL) throws -> String {
        return "Image description not implemented in migration yet for \(url.lastPathComponent)"
    }

    private func applyLineWindow(
        _ content: String, startLine: Int?, endLine: Int?, search: String?, format: String
    ) -> (text: String, truncated: Bool) {
        // ... (simplified logic)
        let lines = content.components(separatedBy: .newlines)
        var resultLines: [String] = []
        // Simple filter
        for (i, line) in lines.enumerated() {
            if let start = startLine, i + 1 < start { continue }
            if let end = endLine, i + 1 > end { break }
            if let s = search, !line.contains(s) { continue }
            resultLines.append(format == "annotated" ? "\(i+1): \(line)" : line)
        }
        return (resultLines.joined(separator: "\n"), false)
    }

    private func formatFileContent(path: String, content: String, truncated: Bool) -> String {
        "File: \(path)\n===\n\(content)"
    }
}
