//
//  ModelFetchService.swift
//  llmHub
//
//  Created by AI Assistant on 12/07/25.
//

import Foundation
import OSLog

/// Service responsible for fetching available models from LLM providers.
///
/// Handles both dynamic model fetching (OpenAI, Google, Mistral, OpenRouter)
/// and curated static lists (Anthropic, xAI) for providers without model endpoints.
@MainActor
final class ModelFetchService {
    
    private let keychainStore = KeychainStore()
    private let logger = Logger(subsystem: "com.llmhub.app", category: "ModelFetchService")
    
    // MARK: - Public Methods
    
    /// Fetches models for a specific provider.
    /// - Parameter provider: The provider to fetch models for
    /// - Returns: Array of available LLMModel instances
    func fetchModels(for provider: KeychainStore.ProviderKey) async throws -> [LLMModel] {
        logger.info("Fetching models for \(provider.rawValue)")
        
        switch provider {
        case .anthropic:
            return getCuratedAnthropicModels()
        case .xai:
            return getCuratedXAIModels()
        case .openAI:
            return try await fetchOpenAIModels()
        case .google:
            return try await fetchGoogleModels()
        case .mistral:
            return try await fetchMistralModels()
        case .openRouter:
            return try await fetchOpenRouterModels()
        }
    }
    
    // MARK: - Curated Model Lists
    
    /// Returns curated list of Anthropic Claude models (no API endpoint available).
    private func getCuratedAnthropicModels() -> [LLMModel] {
        logger.info("Using curated Anthropic model list")
        
        return [
            LLMModel(
                id: "claude-opus-4-5-20250514",
                name: "Claude Opus 4.5",
                maxOutputTokens: 16_384,
                contextWindow: 200_000,
                supportsToolUse: true
            ),
            LLMModel(
                id: "claude-sonnet-4-5-20250514",
                name: "Claude Sonnet 4.5",
                maxOutputTokens: 16_384,
                contextWindow: 200_000,
                supportsToolUse: true
            ),
            LLMModel(
                id: "claude-haiku-4-5-20250514",
                name: "Claude Haiku 4.5",
                maxOutputTokens: 16_384,
                contextWindow: 200_000,
                supportsToolUse: true
            ),
            // Legacy models still available
            LLMModel(
                id: "claude-3-5-sonnet-20241022",
                name: "Claude 3.5 Sonnet",
                maxOutputTokens: 8_192,
                contextWindow: 200_000,
                supportsToolUse: true
            ),
            LLMModel(
                id: "claude-3-5-haiku-20241022",
                name: "Claude 3.5 Haiku",
                maxOutputTokens: 8_192,
                contextWindow: 200_000,
                supportsToolUse: true
            ),
            LLMModel(
                id: "claude-3-opus-20240229",
                name: "Claude 3 Opus",
                maxOutputTokens: 4_096,
                contextWindow: 200_000,
                supportsToolUse: true
            ),
        ]
    }
    
    /// Returns curated list of xAI Grok models (no API endpoint available).
    private func getCuratedXAIModels() -> [LLMModel] {
        logger.info("Using curated xAI model list")
        
        return [
            LLMModel(
                id: "grok-4-1-0125",
                name: "Grok 4.1",
                maxOutputTokens: 16_384,
                contextWindow: 128_000,
                supportsToolUse: true
            ),
            LLMModel(
                id: "grok-4-0125",
                name: "Grok 4",
                maxOutputTokens: 16_384,
                contextWindow: 128_000,
                supportsToolUse: true
            ),
            LLMModel(
                id: "grok-3-mini",
                name: "Grok 3 Mini",
                maxOutputTokens: 8_192,
                contextWindow: 128_000,
                supportsToolUse: true
            ),
            LLMModel(
                id: "grok-2-vision-1212",
                name: "Grok 2 Vision",
                maxOutputTokens: 8_192,
                contextWindow: 32_000,
                supportsToolUse: false
            ),
            LLMModel(
                id: "grok-2-1212",
                name: "Grok 2",
                maxOutputTokens: 8_192,
                contextWindow: 32_000,
                supportsToolUse: true
            ),
        ]
    }
    
    // MARK: - Dynamic Model Fetching
    
    /// Fetches available models from OpenAI API.
    private func fetchOpenAIModels() async throws -> [LLMModel] {
        guard let apiKey = keychainStore.apiKey(for: .openAI) else {
            throw ModelFetchError.noAPIKey
        }
        
        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelFetchError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw ModelFetchError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        let modelResponse = try decoder.decode(OpenAIModelsResponse.self, from: data)
        
        // Filter and map to our model format
        let models = modelResponse.data
            .filter { model in
                // Only include GPT models and o-series models
                model.id.contains("gpt") || model.id.hasPrefix("o1") || model.id.hasPrefix("o3")
            }
            .sorted { $0.created > $1.created } // Newest first
            .map { apiModel -> LLMModel in
                parseOpenAIModel(apiModel)
            }
        
        logger.info("Fetched \(models.count) OpenAI models")
        return models
    }
    
    /// Parses an OpenAI API model into our LLMModel format.
    private func parseOpenAIModel(_ apiModel: OpenAIModel) -> LLMModel {
        let id = apiModel.id
        
        // Determine context window and output limits based on model ID
        let contextWindow: Int
        let maxOutputTokens: Int
        let supportsToolUse: Bool
        
        if id.contains("gpt-4o") {
            contextWindow = 128_000
            maxOutputTokens = 16_384
            supportsToolUse = true
        } else if id.contains("gpt-4-turbo") || id.contains("gpt-4-1106") {
            contextWindow = 128_000
            maxOutputTokens = 4_096
            supportsToolUse = true
        } else if id.contains("gpt-4") {
            contextWindow = 8_192
            maxOutputTokens = 8_192
            supportsToolUse = true
        } else if id.contains("gpt-3.5") {
            contextWindow = 16_385
            maxOutputTokens = 4_096
            supportsToolUse = true
        } else if id.hasPrefix("o1") || id.hasPrefix("o3") {
            contextWindow = 200_000
            maxOutputTokens = 100_000
            supportsToolUse = false // o1/o3 don't support tools yet
        } else {
            contextWindow = 8_192
            maxOutputTokens = 4_096
            supportsToolUse = false
        }
        
        return LLMModel(
            id: id,
            name: formatModelName(id),
            maxOutputTokens: maxOutputTokens,
            contextWindow: contextWindow,
            supportsToolUse: supportsToolUse
        )
    }
    
    /// Fetches available models from Google AI API.
    private func fetchGoogleModels() async throws -> [LLMModel] {
        guard let apiKey = keychainStore.apiKey(for: .google) else {
            throw ModelFetchError.noAPIKey
        }
        
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)")!
        var request = URLRequest(url: url)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelFetchError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw ModelFetchError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let modelResponse = try decoder.decode(GoogleModelsResponse.self, from: data)
        
        // Filter for generative models and map to our format
        let models = modelResponse.models
            .filter { model in
                model.name.contains("gemini") && 
                model.supportedGenerationMethods.contains("generateContent")
            }
            .map { apiModel -> LLMModel in
                parseGoogleModel(apiModel)
            }
        
        logger.info("Fetched \(models.count) Google AI models")
        return models
    }
    
    /// Parses a Google AI API model into our LLMModel format.
    private func parseGoogleModel(_ apiModel: GoogleModel) -> LLMModel {
        // Extract model ID (e.g., "models/gemini-2.0-flash" -> "gemini-2.0-flash")
        let id = apiModel.name.replacingOccurrences(of: "models/", with: "")
        
        let contextWindow = apiModel.inputTokenLimit ?? 128_000
        let maxOutputTokens = apiModel.outputTokenLimit ?? 8_192
        
        return LLMModel(
            id: id,
            name: formatModelName(id),
            maxOutputTokens: maxOutputTokens,
            contextWindow: contextWindow,
            supportsToolUse: true // All Gemini models support tools
        )
    }
    
    /// Fetches available models from Mistral AI API.
    private func fetchMistralModels() async throws -> [LLMModel] {
        guard let apiKey = keychainStore.apiKey(for: .mistral) else {
            throw ModelFetchError.noAPIKey
        }
        
        let url = URL(string: "https://api.mistral.ai/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelFetchError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw ModelFetchError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        let modelResponse = try decoder.decode(MistralModelsResponse.self, from: data)
        
        let models = modelResponse.data.map { apiModel -> LLMModel in
            parseMistralModel(apiModel)
        }
        
        logger.info("Fetched \(models.count) Mistral AI models")
        return models
    }
    
    /// Parses a Mistral AI API model into our LLMModel format.
    private func parseMistralModel(_ apiModel: MistralModel) -> LLMModel {
        let id = apiModel.id
        
        // Mistral models have varying context windows
        let contextWindow: Int
        let maxOutputTokens: Int
        
        if id.contains("large") {
            contextWindow = 128_000
            maxOutputTokens = 16_384
        } else if id.contains("small") || id.contains("medium") {
            contextWindow = 32_000
            maxOutputTokens = 8_192
        } else {
            contextWindow = apiModel.maxContextLength ?? 32_000
            maxOutputTokens = 8_192
        }
        
        return LLMModel(
            id: id,
            name: formatModelName(id),
            maxOutputTokens: maxOutputTokens,
            contextWindow: contextWindow,
            supportsToolUse: true // Most Mistral models support tools
        )
    }
    
    /// Fetches available models from OpenRouter API.
    private func fetchOpenRouterModels() async throws -> [LLMModel] {
        guard let apiKey = keychainStore.apiKey(for: .openRouter) else {
            throw ModelFetchError.noAPIKey
        }
        
        let url = URL(string: "https://openrouter.ai/api/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelFetchError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw ModelFetchError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let modelResponse = try decoder.decode(OpenRouterModelsResponse.self, from: data)
        
        let models = modelResponse.data.map { apiModel -> LLMModel in
            parseOpenRouterModel(apiModel)
        }
        
        logger.info("Fetched \(models.count) OpenRouter models")
        return models
    }
    
    /// Parses an OpenRouter API model into our LLMModel format.
    private func parseOpenRouterModel(_ apiModel: OpenRouterModel) -> LLMModel {
        return LLMModel(
            id: apiModel.id,
            name: apiModel.name ?? formatModelName(apiModel.id),
            maxOutputTokens: apiModel.topProvider?.maxCompletionTokens ?? 4_096,
            contextWindow: apiModel.contextLength ?? 8_192,
            supportsToolUse: true // Most OpenRouter models support tools
        )
    }
    
    // MARK: - Helper Methods
    
    /// Formats a model ID into a human-readable display name.
    private func formatModelName(_ id: String) -> String {
        // Convert "gpt-4o-mini" -> "GPT-4o Mini"
        // Convert "gemini-2.0-flash-exp" -> "Gemini 2.0 Flash Exp"
        
        return id
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - API Response Models

// OpenAI
private struct OpenAIModelsResponse: Codable {
    let data: [OpenAIModel]
}

private struct OpenAIModel: Codable {
    let id: String
    let created: Int
    let ownedBy: String
    
    enum CodingKeys: String, CodingKey {
        case id, created
        case ownedBy = "owned_by"
    }
}

// Google AI
private struct GoogleModelsResponse: Codable {
    let models: [GoogleModel]
}

private struct GoogleModel: Codable {
    let name: String
    let displayName: String
    let description: String
    let inputTokenLimit: Int?
    let outputTokenLimit: Int?
    let supportedGenerationMethods: [String]
}

// Mistral AI
private struct MistralModelsResponse: Codable {
    let data: [MistralModel]
}

private struct MistralModel: Codable {
    let id: String
    let object: String
    let created: Int
    let ownedBy: String
    let capabilities: MistralCapabilities?
    let maxContextLength: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, object, created
        case ownedBy = "owned_by"
        case capabilities
        case maxContextLength = "max_context_length"
    }
}

private struct MistralCapabilities: Codable {
    let completionChat: Bool?
    let completionFim: Bool?
    let functionCalling: Bool?
    
    enum CodingKeys: String, CodingKey {
        case completionChat = "completion_chat"
        case completionFim = "completion_fim"
        case functionCalling = "function_calling"
    }
}

// OpenRouter
private struct OpenRouterModelsResponse: Codable {
    let data: [OpenRouterModel]
}

private struct OpenRouterModel: Codable {
    let id: String
    let name: String?
    let description: String?
    let pricing: OpenRouterPricing?
    let contextLength: Int?
    let architecture: OpenRouterArchitecture?
    let topProvider: OpenRouterProvider?
}

private struct OpenRouterPricing: Codable {
    let prompt: String?
    let completion: String?
}

private struct OpenRouterArchitecture: Codable {
    let modality: String?
    let tokenizer: String?
    let instructType: String?
}

private struct OpenRouterProvider: Codable {
    let maxCompletionTokens: Int?
}

// MARK: - Errors

enum ModelFetchError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured for provider"
        case .invalidResponse:
            return "Invalid response from API"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
