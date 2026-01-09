//
//  ModelsDevModel.swift
//  llmHub
//
//  Model metadata from models.dev API
//  API: https://models.dev/api.json
//

import Foundation

/// Model metadata from models.dev API
/// Maps to the JSON schema at https://models.dev/api.json
struct ModelsDevModel: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let cost: Cost?
    let limit: Limit?
    let toolCall: Bool?
    let reasoning: Bool?
    let attachment: Bool?
    let modalities: Modalities?

    struct Cost: Codable, Sendable {
        let input: Double?       // per 1M tokens
        let output: Double?      // per 1M tokens
        let cacheRead: Double?   // per 1M tokens
        let cacheWrite: Double?  // per 1M tokens

        enum CodingKeys: String, CodingKey {
            case input
            case output
            case cacheRead = "cache_read"
            case cacheWrite = "cache_write"
        }
    }

    struct Limit: Codable, Sendable {
        let context: Int?
        let output: Int?
    }

    struct Modalities: Codable, Sendable {
        let input: [String]?
        let output: [String]?
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case cost
        case limit
        case toolCall = "tool_call"
        case reasoning
        case attachment
        case modalities
    }
}

// MARK: - Conversion to LLMModel

extension ModelsDevModel {
    /// Convert to existing LLMModel type for compatibility with the rest of the app
    func toLLMModel() -> LLMModel {
        return LLMModel(
            id: id,
            name: name,
            maxOutputTokens: limit?.output ?? 4096,
            contextWindow: limit?.context ?? 8192,
            supportsToolUse: toolCall ?? false
        )
    }
}

// MARK: - API Response Structure

/// Wrapper for provider data from models.dev API
struct ModelsDevProvider: Codable, Sendable {
    let id: String
    let name: String?
    let models: [String: ModelsDevModel]

    // Additional fields that may be present but we don't need
    let env: [String]?
    let npm: String?
    let api: String?
    let doc: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case models
        case env
        case npm
        case api
        case doc
    }
}

// Note: The models.dev API returns a dictionary [String: ModelsDevProvider]
// where keys are provider names (e.g., "anthropic", "openai", "google")
// and values contain provider metadata with a nested models dictionary
