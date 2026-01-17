//
//  ArtifactListTool.swift
//  llmHub
//
//  Lists all artifacts in the sandbox for model access.
//

import Foundation

/// Tool to list all available artifacts in the sandbox.
nonisolated struct ArtifactListTool: Tool {
    let name = "artifact_list"
    let description = """
        List all files available in the artifact library. \
        Returns an array of artifacts with id, name, mimeType, and bytes. \
        Use this to discover what files the user has shared for this conversation.
        """

    nonisolated var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [:],
            required: []
        )
    }

    let permissionLevel: ToolPermissionLevel = .sensitive
    let requiredCapabilities: [ToolCapability] = []
    let weight: ToolWeight = .fast
    let isCacheable = false

    init() {}

    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws
        -> ToolResult
    {
        let artifacts = await ArtifactSandboxService.shared.listArtifacts()

        if artifacts.isEmpty {
            return ToolResult.success(
                "No artifacts available. The user has not shared any files yet.",
                metadata: ["count": "0"],
                truncated: false
            )
        }

        // Build JSON array of artifact metadata (no paths)
        let items: [[String: Any]] = artifacts.map { artifact in
            [
                "id": artifact.id.uuidString,
                "name": artifact.filename,
                "mimeType": artifact.mimeType,
                "bytes": artifact.sizeBytes,
            ]
        }

        let jsonData = try JSONSerialization.data(withJSONObject: items, options: .prettyPrinted)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"

        return ToolResult.success(
            jsonString,
            metadata: ["count": String(artifacts.count)],
            truncated: false
        )
    }
}
