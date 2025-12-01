//
//  UIModels.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import Foundation
import SwiftUI

// MARK: - LLM Provider Models

struct UILLMProvider: Identifiable, Hashable {
    let id: UUID
    let name: String
    let icon: String
    let models: [UILLMModel]
    var isActive: Bool

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

struct UILLMModel: Identifiable, Hashable {
    let id: UUID
    let name: String
    let contextWindow: Int
}

// MARK: - Tool Models

struct UIToolDefinition: Identifiable {
    let id: UUID
    let name: String
    let icon: String
    let description: String

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

struct ToolExecution: Identifiable {
    let id: UUID
    let name: String
    let icon: String
    let status: ExecutionStatus
    let output: String
    let timestamp: Date

    enum ExecutionStatus {
        case pending
        case running
        case success
        case error

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
