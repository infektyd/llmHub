//
//  LLMProviderProtocol.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import Foundation

protocol LLMProvider: Identifiable {
    var id: String { get }
    var name: String { get }
    var endpoint: URL { get }
    var supportsStreaming: Bool { get }
    var availableModels: [LLMModel] { get }
    var defaultHeaders: [String: String] { get }
    var pricing: PricingMetadata { get }
    var isConfigured: Bool { get }

    func fetchModels() async throws -> [LLMModel]
    func buildRequest(messages: [ChatMessage], model: String) throws -> URLRequest
    func buildRequest(messages: [ChatMessage], model: String, tools: [ToolDefinition]?) throws -> URLRequest
    func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error>
    func parseTokenUsage(from response: Data) throws -> TokenUsage?
}

/// Tool definition for LLM function calling
struct ToolDefinition: Sendable {
    let name: String
    let description: String
    let inputSchema: [String: Any]
    
    init(from tool: any Tool) {
        self.name = tool.name
        self.description = tool.description
        self.inputSchema = tool.inputSchema
    }
}

// Default implementation for providers that don't support tools yet
extension LLMProvider {
    func buildRequest(messages: [ChatMessage], model: String, tools: [ToolDefinition]?) throws -> URLRequest {
        // Default: ignore tools, just build regular request
        try buildRequest(messages: messages, model: model)
    }
}

struct LLMModel: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let contextWindow: Int
    let supportsToolUse: Bool
    let maxOutputTokens: Int
}

extension LLMModel {
    init(id: String, name: String, maxOutputTokens: Int, contextWindow: Int = 128_000, supportsToolUse: Bool = true) {
        self.id = id
        self.displayName = name
        self.contextWindow = contextWindow
        self.supportsToolUse = supportsToolUse
        self.maxOutputTokens = maxOutputTokens
    }
}

struct PricingMetadata: Sendable {
    var inputPer1KUSD: Decimal
    var outputPer1KUSD: Decimal
    var currency: String
}

enum ProviderEvent: Sendable {
    case token(text: String)
    case thinking(String) // Add this back
    case toolUse(id: String, name: String, input: String)
    case completion(message: ChatMessage)
    case usage(TokenUsage)
    case reference(String)
    case error(LLMProviderError)
}

enum LLMProviderError: LocalizedError, Sendable {
    case invalidRequest
    case authenticationMissing
    case rateLimited(retryAfter: TimeInterval?)
    case decodingFailed
    case server(reason: String)
    case network(URLError)

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "Invalid request payload."
        case .authenticationMissing: "Missing API key for provider."
        case .rateLimited(let retryAfter): "Rate limited. Retry after: \(retryAfter?.description ?? "unknown")."
        case .decodingFailed: "Failed to decode provider response."
        case .server(let reason): "Provider error: \(reason)"
        case .network(let error): "Network error: \(error.localizedDescription)"
        }
    }
}
