//
//  ArtifactOpenTool.swift
//  llmHub
//
//  Returns metadata for a single artifact by ID.
//

import Foundation

/// Tool to get metadata for a specific artifact by ID.
nonisolated struct ArtifactOpenTool: Tool {
    let name = "artifact_open"
    let description = """
        Get metadata for a specific artifact by its ID. \
        Returns id, name, mimeType, bytes, and importedAt. \
        Use artifact_list first to discover available artifact IDs.
        """

    nonisolated var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "id": ToolProperty(
                    type: .string,
                    description: "The artifact ID to retrieve metadata for."
                )
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

        // Treat ID as opaque string, try UUID parse for sandbox lookup
        guard let uuid = UUID(uuidString: idString) else {
            throw ToolError.invalidArguments("Invalid artifact ID format: \(idString)")
        }

        guard let artifact = await ArtifactSandboxService.shared.artifact(id: uuid) else {
            throw ToolError.executionFailed(
                "Artifact not found: \(idString). Use artifact_list to see available artifacts."
            )
        }

        let metadata: [String: Any] = [
            "id": artifact.id.uuidString,
            "name": artifact.filename,
            "mimeType": artifact.mimeType,
            "bytes": artifact.sizeBytes,
            "importedAt": ISO8601DateFormatter().string(from: artifact.importedAt),
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return ToolResult(
            content: jsonString,
            metrics: .empty,
            metadata: ["id": idString],
            truncated: false
        )
    }
}
