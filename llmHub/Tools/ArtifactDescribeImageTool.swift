//
//  ArtifactDescribeImageTool.swift
//  llmHub
//
//  Returns metadata for image artifacts (stub for future vision integration).
//

import Foundation
import ImageIO

/// Tool to describe an image artifact (stub implementation).
nonisolated struct ArtifactDescribeImageTool: Tool {
    let name = "artifact_describe_image"
    let description = """
        Get information about an image artifact. \
        Returns mimeType, bytes, filename, and dimensions if available. \
        Full image description via vision is not yet implemented.
        """

    nonisolated var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "id": ToolProperty(
                    type: .string,
                    description: "The artifact ID of the image to describe."
                ),
                "detail": ToolProperty(
                    type: .string,
                    description: "Detail level (reserved for future use): 'low' or 'high'."
                ),
            ],
            required: ["id"]
        )
    }

    let permissionLevel: ToolPermissionLevel = .readOnly
    let requiredCapabilities: [ToolCapability] = []
    let weight: ToolWeight = .fast
    let isCacheable = true

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

        // Validate image mime type
        guard artifact.mimeType.hasPrefix("image/") else {
            throw ToolError.executionFailed(
                "Not an image artifact: \(artifact.filename) (type: \(artifact.mimeType)). "
                    + "Use artifact_read_text for text files."
            )
        }

        let fileURL = await ArtifactSandboxService.shared.artifactPath(for: artifact)

        // Try to get image dimensions
        var width: Int?
        var height: Int?
        if let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) {
            if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
                as? [CFString: Any]
            {
                width = properties[kCGImagePropertyPixelWidth] as? Int
                height = properties[kCGImagePropertyPixelHeight] as? Int
            }
        }

        var result: [String: Any] = [
            "id": artifact.id.uuidString,
            "filename": artifact.filename,
            "mimeType": artifact.mimeType,
            "bytes": artifact.sizeBytes,
            "description": "Image description not yet implemented. Vision integration planned.",
        ]

        if let w = width, let h = height {
            result["dimensions"] = ["width": w, "height": h]
        }

        let jsonData = try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return ToolResult(
            content: jsonString,
            metrics: .empty,
            metadata: ["id": idString],
            truncated: false
        )
    }
}
