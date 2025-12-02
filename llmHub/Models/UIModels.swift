//
//  UIModels.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import Foundation
import SwiftUI

// MARK: - LLM Provider Models

/// Represents a Large Language Model (LLM) provider in the UI.
struct UILLMProvider: Identifiable, Hashable {
    /// The unique identifier of the provider.
    let id: UUID
    /// The display name of the provider (e.g., "OpenAI").
    let name: String
    /// The system image name for the provider's icon.
    let icon: String
    /// The list of models offered by this provider.
    let models: [UILLMModel]
    /// Indicates if this provider is currently active/selected.
    var isActive: Bool

    /// A list of sample providers for previews and testing.
    static let sampleProviders: [UILLMProvider] = [
        UILLMProvider(
            id: UUID(),
            name: "Anthropic",
            icon: "brain.head.profile",
            models: [
                UILLMModel(id: UUID(), name: "Claude 3.5 Sonnet", contextWindow: 200000),
                UILLMModel(id: UUID(), name: "Claude 3 Opus", contextWindow: 200000),
                UILLMModel(id: UUID(), name: "Claude 3 Haiku", contextWindow: 200000),
            ],
            isActive: true
        ),
        UILLMProvider(
            id: UUID(),
            name: "OpenAI",
            icon: "sparkles",
            models: [
                UILLMModel(id: UUID(), name: "GPT-4 Turbo", contextWindow: 128000),
                UILLMModel(id: UUID(), name: "GPT-4", contextWindow: 8192),
                UILLMModel(id: UUID(), name: "GPT-3.5 Turbo", contextWindow: 16385),
            ],
            isActive: false
        ),
        UILLMProvider(
            id: UUID(),
            name: "Google",
            icon: "cloud.fill",
            models: [
                UILLMModel(id: UUID(), name: "Gemini Pro", contextWindow: 32000),
                UILLMModel(id: UUID(), name: "Gemini Ultra", contextWindow: 32000),
            ],
            isActive: false
        ),
    ]
}

/// Represents a specific model from an LLM provider.
struct UILLMModel: Identifiable, Hashable {
    /// The unique identifier of the model.
    let id: UUID
    /// The display name of the model (e.g., "GPT-4").
    let name: String
    /// The context window size of the model in tokens.
    let contextWindow: Int
}

// MARK: - Tool Models

/// Defines a tool available in the UI.
struct UIToolDefinition: Identifiable {
    /// The unique identifier of the tool.
    let id: UUID
    /// The display name of the tool.
    let name: String
    /// The system image name for the tool's icon.
    let icon: String
    /// A description of what the tool does.
    let description: String

    /// A list of sample tools for previews and testing.
    static let sampleTools: [UIToolDefinition] = [
        UIToolDefinition(
            id: UUID(),
            name: "Code Interpreter",
            icon: "curlybraces",
            description: "Execute code snippets"
        ),
        UIToolDefinition(
            id: UUID(),
            name: "Web Search",
            icon: "magnifyingglass.circle.fill",
            description: "Search the web"
        ),
        UIToolDefinition(
            id: UUID(),
            name: "File Reader",
            icon: "doc.text.fill",
            description: "Read file contents"
        ),
        UIToolDefinition(
            id: UUID(),
            name: "File Editor",
            icon: "pencil.circle.fill",
            description: "Edit files"
        ),
        UIToolDefinition(
            id: UUID(),
            name: "Terminal",
            icon: "terminal.fill",
            description: "Execute shell commands"
        ),
    ]
}

/// Represents the execution state of a tool.
struct ToolExecution: Identifiable {
    /// The unique identifier of the execution.
    let id: UUID
    /// The name of the tool being executed.
    let name: String
    /// The icon name of the tool.
    let icon: String
    /// The current status of the execution.
    let status: ExecutionStatus
    /// The output or logs from the execution.
    let output: String
    /// The timestamp when the execution started.
    let timestamp: Date

    /// The possible states of a tool execution.
    enum ExecutionStatus {
        /// The execution is waiting to start.
        case pending
        /// The execution is currently running.
        case running
        /// The execution completed successfully.
        case success
        /// The execution failed.
        case error

        /// The color associated with the status.
        var color: Color {
            switch self {
            case .pending: return .neonGray
            case .running: return .neonElectricBlue
            case .success: return .green
            case .error: return .neonFuchsia
            }
        }
    }
}
