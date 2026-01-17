//
//  ArtifactReadTextTool.swift
//  llmHub
//
//  Reads text content from an artifact with guardrails.
//

import Foundation

/// Tool to read text content from an artifact.
nonisolated struct ArtifactReadTextTool: Tool {
    let name = "artifact_read_text"
    let description = """
        Read text content from an artifact file. \
        Returns a bounded excerpt with truncation indicator if content exceeds limits. \
        Only works for text-based files (text/*, application/json, etc.). \
        Use artifact_list to discover artifact IDs first.
        """

    nonisolated var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "id": ToolProperty(
                    type: .string,
                    description: "The artifact ID to read."
                ),
                "maxChars": ToolProperty(
                    type: .integer,
                    description: "Maximum characters to return (default: 10000, max: 50000)."
                ),
                "offset": ToolProperty(
                    type: .integer,
                    description: "Character offset to start reading from (default: 0)."
                ),
            ],
            required: ["id"]
        )
    }

    let permissionLevel: ToolPermissionLevel = .sensitive
    let requiredCapabilities: [ToolCapability] = [.fileSystem]
    let weight: ToolWeight = .heavy
    let isCacheable = true

    private let maxBytesRead = 50 * 1024  // 50KB max disk read
    private let defaultMaxChars = 10000
    private let absoluteMaxChars = 50000

    init() {}

    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws
        -> ToolResult
    {
        guard let idString = arguments.string("id"), !idString.isEmpty else {
            throw ToolError.invalidArguments("id is required")
        }

        guard let uuid = UUID(uuidString: idString) else {
            throw ToolError.invalidArguments("Invalid artifact ID format: \(idString)")
        }

        guard let artifact = await ArtifactSandboxService.shared.artifact(id: uuid) else {
            throw ToolError.executionFailed(
                "Artifact not found: \(idString). Use artifact_list to see available artifacts."
            )
        }

        // Validate text-based mime type
        let textMimeTypes = [
            "text/", "application/json", "application/xml", "application/javascript",
            "application/x-yaml", "application/toml",
        ]
        let isTextType = textMimeTypes.contains { artifact.mimeType.hasPrefix($0) }
        if !isTextType {
            throw ToolError.executionFailed(
                "Cannot read non-text artifact: \(artifact.filename) (type: \(artifact.mimeType)). "
                    + "Use artifact_describe_image for images."
            )
        }

        let maxChars = min(
            arguments.int("maxChars") ?? defaultMaxChars,
            absoluteMaxChars
        )
        let offset = max(arguments.int("offset") ?? 0, 0)

        // Get file URL from sandbox
        let fileURL = await ArtifactSandboxService.shared.artifactPath(for: artifact)

        // Read with byte limit
        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw ToolError.executionFailed(
                "Failed to open artifact: \(error.localizedDescription)")
        }
        defer { try? fileHandle.close() }

        let data = fileHandle.readData(ofLength: maxBytesRead)

        // Decode UTF-8 gracefully
        guard let fullContent = String(data: data, encoding: .utf8) else {
            throw ToolError.executionFailed(
                "Failed to decode artifact as UTF-8 text. File may be binary or use unsupported encoding."
            )
        }

        // Apply offset and limit
        let startIndex = fullContent.index(
            fullContent.startIndex,
            offsetBy: min(offset, fullContent.count)
        )
        let endIndex =
            fullContent.index(
                startIndex,
                offsetBy: min(maxChars, fullContent.count - offset),
                limitedBy: fullContent.endIndex
            ) ?? fullContent.endIndex

        let excerpt = String(fullContent[startIndex..<endIndex])
        let truncated = endIndex < fullContent.endIndex || data.count >= maxBytesRead

        var result: [String: Any] = [
            "content": excerpt,
            "filename": artifact.filename,
            "mimeType": artifact.mimeType,
            "offset": offset,
            "length": excerpt.count,
        ]
        if truncated {
            result["truncated"] = true
            result["nextOffset"] = offset + excerpt.count
        }

        let jsonData = try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return ToolResult.success(
            jsonString,
            metadata: ["id": idString, "bytes_read": String(data.count)],
            truncated: truncated
        )
    }
}
