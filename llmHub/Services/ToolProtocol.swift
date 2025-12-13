// Services/ToolProtocol.swift
// Unified tool abstraction for llmHub

import Foundation

// MARK: - Tool Protocol

/// Unified protocol for all tools in llmHub.
/// Conforms to Sendable for safe concurrent access.
protocol Tool: Sendable {
    /// Unique identifier (e.g., "http_request", "shell")
    nonisolated var name: String { get }

    /// Human-readable description for LLM system prompt
    nonisolated var description: String { get }

    /// JSON Schema for input parameters
    nonisolated var parameters: ToolParametersSchema { get }

    /// Permission level for authorization
    nonisolated var permissionLevel: ToolPermissionLevel { get }

    /// Capabilities required to run
    nonisolated var requiredCapabilities: [ToolCapability] { get }

    /// Execution weight for scheduling
    nonisolated var weight: ToolWeight { get }

    /// Whether results can be cached
    nonisolated var isCacheable: Bool { get }

    /// Check availability in given environment
    nonisolated func availability(in environment: ToolEnvironment) -> ToolAvailability

    /// Execute the tool
    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult
}

// MARK: - Default Implementations

extension Tool {
    nonisolated var requiredCapabilities: [ToolCapability] { [] }
    nonisolated var weight: ToolWeight { .fast }
    nonisolated var isCacheable: Bool { false }

    nonisolated func availability(in environment: ToolEnvironment) -> ToolAvailability {
        environment.availability(for: requiredCapabilities)
    }

    /// Estimated token cost for context budgeting
    func estimateDefinitionTokens() -> Int {
        let baseText = name + description
        let schemaCost = parameters.properties.count * 10
        return (baseText.count / 4) + schemaCost
    }
}
