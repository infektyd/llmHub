//
//  ModelMetadataFallback.swift
//  llmHub
//
//  Created by AI Assistant on 12/01/26.
//

import Foundation

/// Provides fallback metadata for models when the API response is incomplete.
/// Sources are documented for each provider.
struct ModelMetadataFallback {

    /// Returns fallback metadata for a given model ID and provider.
    /// - Parameters:
    ///   - modelID: The model identifier.
    ///   - provider: The provider key.
    /// - Returns: A tuple of (contextWindow, maxOutputTokens, supportsToolUse) if known, else defaults.
    static func getMetadata(for modelID: String, provider: KeychainStore.ProviderKey) -> (
        contextWindow: Int, maxOutputTokens: Int, supportsToolUse: Bool
    ) {
        switch provider {
        case .openai:
            return openAIFallback(for: modelID)
        case .mistral:
            return mistralFallback(for: modelID)
        case .xai:
            return xAIFallback(for: modelID)
        case .anthropic:
            return anthropicFallback(for: modelID)
        default:
            // Generic conservative defaults
            return (8_192, 4_096, true)
        }
    }

    // MARK: - OpenAI
    // Source: https://platform.openai.com/docs/models
    private static func openAIFallback(for id: String) -> (Int, Int, Bool) {
        if id.contains("gpt-4o") {
            return (128_000, 16_384, true)
        } else if id.contains("gpt-4-turbo") || id.contains("gpt-4-1106") {
            return (128_000, 4_096, true)
        } else if id.contains("gpt-4") {
            return (8_192, 8_192, true)
        } else if id.contains("gpt-3.5") {
            return (16_385, 4_096, true)
        } else if id.hasPrefix("o1") || id.hasPrefix("o3") {
            // o1/o3: 200k context (beta limitations apply to tools)
            return (200_000, 100_000, false)
        }
        return (8_192, 4_096, false)
    }

    // MARK: - Mistral
    // Source: https://docs.mistral.ai/getting-started/models/
    private static func mistralFallback(for id: String) -> (Int, Int, Bool) {
        if id.contains("large") {
            return (128_000, 16_384, true)
        } else if id.contains("codestral") {
            return (32_000, 8_192, true)
        } else if id.contains("small") || id.contains("medium") {
            return (32_000, 8_192, true)
        }
        return (32_000, 8_192, true)
    }

    // MARK: - xAI
    // Source: https://docs.x.ai/
    private static func xAIFallback(for id: String) -> (Int, Int, Bool) {
        // Grok 2 models: 128k context
        if id.contains("grok-2") || id.contains("grok-beta") {
            return (128_000, 8_192, true)
        }
        // Grok 1: 128k
        return (128_000, 8_192, true)
    }

    // MARK: - Anthropic
    // Source: https://docs.anthropic.com/en/docs/about-claude/models
    private static func anthropicFallback(for id: String) -> (Int, Int, Bool) {
        // Claude 3 and 3.5: 200k context
        if id.contains("claude-3") {
            return (200_000, 8_192, true)
        }
        // Older models (Claude 2): 100k
        if id.contains("claude-2") {
            return (100_000, 4_096, true)
        }
        return (200_000, 4_096, true)
    }
}
