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
                UILLMModel(
                    id: UUID(), modelID: "claude-sonnet-4-20250514", name: "Claude Sonnet 4",
                    contextWindow: 200000),
                UILLMModel(
                    id: UUID(), modelID: "claude-opus-4-20250514", name: "Claude Opus 4",
                    contextWindow: 200000),
                UILLMModel(
                    id: UUID(), modelID: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku",
                    contextWindow: 200000),
            ],
            isActive: true
        ),
        UILLMProvider(
            id: UUID(),
            name: "OpenAI",
            icon: "sparkles",
            models: [
                UILLMModel(
                    id: UUID(), modelID: "gpt-4-turbo", name: "GPT-4 Turbo", contextWindow: 128000),
                UILLMModel(id: UUID(), modelID: "gpt-4", name: "GPT-4", contextWindow: 8192),
                UILLMModel(
                    id: UUID(), modelID: "gpt-3.5-turbo", name: "GPT-3.5 Turbo",
                    contextWindow: 16385),
            ],
            isActive: false
        ),
        UILLMProvider(
            id: UUID(),
            name: "Google",
            icon: "cloud.fill",
            models: [
                UILLMModel(
                    id: UUID(), modelID: "gemini-1.5-pro", name: "Gemini Pro", contextWindow: 32000),
                UILLMModel(
                    id: UUID(), modelID: "gemini-1.0-ultra", name: "Gemini Ultra",
                    contextWindow: 32000),
            ],
            isActive: false
        ),
    ]
}

/// Represents a specific model from an LLM provider.
struct UILLMModel: Identifiable, Hashable {
    /// The unique identifier of the model.
    let id: UUID
    /// The actual model ID used for API calls (e.g., "claude-opus-4-20250514").
    let modelID: String
    /// The display name of the model (e.g., "GPT-4").
    let name: String
    /// The context window size of the model in tokens.
    let contextWindow: Int
}

extension UILLMModel {
    /// Represents the pricing tier of a model.
    enum PricingTier {
        case free
        case budget
        case standard
        case premium
        case enterprise

        var displayName: String {
            switch self {
            case .free: return "Free"
            case .budget: return "Budget"
            case .standard: return "Standard"
            case .premium: return "Premium"
            case .enterprise: return "Enterprise"
            }
        }

        var icon: String {
            switch self {
            case .free: return "gift"
            case .budget: return "dollarsign.circle"
            case .standard: return "banknote"
            case .premium: return "crown"
            case .enterprise: return "building.2"
            }
        }

        var color: Color {
            switch self {
            case .free: return .green
            case .budget: return .cyan
            case .standard: return .blue
            case .premium: return .purple
            case .enterprise: return .purple
            }
        }
    }

    /// Infers pricing tier based on context window and model name.
    var pricingTier: PricingTier? {
        let nameLower = name.lowercased()

        // Free models
        if nameLower.contains("free") || nameLower.contains("trial") {
            return .free
        }

        // Budget models (small models, haiku, mini, nano)
        if nameLower.contains("haiku") || nameLower.contains("mini") || nameLower.contains("nano")
            || nameLower.contains("3.5")
        {
            return .budget
        }

        // Premium models (opus, pro, ultra, large context)
        if nameLower.contains("opus") || nameLower.contains("ultra") || contextWindow >= 200_000 {
            return .premium
        }

        // Enterprise models
        if nameLower.contains("enterprise") || nameLower.contains("turbo") {
            return .enterprise
        }

        // Default to standard
        return .standard
    }
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
    static let sampleTools: [UIToolDefinition] = defaultTools(for: ToolEnvironment.current)

    /// Builds tool definitions filtered by environment availability.
    /// - Parameter environment: The current tool environment.
    /// - Returns: Supported tool definitions.
    static func defaultTools(for environment: ToolEnvironment) -> [UIToolDefinition] {
        let baseTools: [(String, String, String, [ToolCapability])] = [
            ("Calculator", "function", "Evaluate quick expressions", []),
            (
                "Code Interpreter", "curlybraces", "Execute multi-language code snippets",
                [.codeExecution]
            ),
            ("Web Search", "magnifyingglass.circle.fill", "Search the web", [.webAccess]),
            ("File Reader", "doc.text.fill", "Read file contents", [.fileRead]),
            ("File Editor", "pencil.circle.fill", "Edit files on disk", [.fileWrite]),
        ]

        return baseTools.compactMap { name, icon, description, capabilities in
            let availability = environment.availability(for: capabilities)
            guard availability.isSupported else { return nil }
            return UIToolDefinition(
                id: UUID(),
                name: name,
                icon: icon,
                description: description
            )
        }
    }
}

// UIToolToggleItem and ToolExecution are now defined in SharedTypes.swift
