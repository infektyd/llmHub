import Foundation
import OSLog

/// Manager for OpenClaw's local gateway — OpenAI-compatible /v1 endpoint.
/// Handles chat completions and model listing against localhost:18789.
public class OpenClawManager {
    private let baseURL: URL
    private let keychain: KeychainStore

    /// Initializes with a configurable base URL (defaults to localhost:18789).
    public init(baseURL: URL = URL(string: "http://localhost:18789/v1")!, keychain: KeychainStore = KeychainStore()) {
        self.baseURL = baseURL
        self.keychain = keychain
    }

    // MARK: - Chat Completion

    /// Creates a URLRequest for chat completion.
    public func makeChatRequest(
        messages: [XAIChatMessage],
        model: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        stream: Bool = false,
        tools: [XAITool]? = nil
    ) async throws -> URLRequest {
        let endpoint = baseURL.appendingPathComponent("chat/completions")

        let payload = XAIChatRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            max_tokens: maxTokens,
            stream: stream,
            tools: tools
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        if let apiKey = await keychain.apiKey(for: .openclaw) {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)

        return request
    }

    // MARK: - List Models

    /// Fetches available models from the gateway's /v1/models endpoint.
    public func listModels() async throws -> [GatewayModel] {
        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let apiKey = await keychain.apiKey(for: .openclaw) {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OpenClawError.gatewayUnreachable
        }

        let decoded = try JSONDecoder().decode(GatewayModelsResponse.self, from: data)
        return decoded.data
    }

    // MARK: - List Agents

    /// Fetches available agents from the gateway's /v1/agents endpoint.
    public func listAgents() async throws -> [GatewayAgent] {
        let url = baseURL.appendingPathComponent("agents")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let apiKey = await keychain.apiKey(for: .openclaw) {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OpenClawError.gatewayUnreachable
        }

        let decoded = try JSONDecoder().decode(GatewayAgentsResponse.self, from: data)
        return decoded.data
    }
}

// MARK: - Models

public enum OpenClawError: LocalizedError {
    case gatewayUnreachable
    case modelNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .gatewayUnreachable:
            return "OpenClaw gateway not reachable at localhost:18789. Is it running?"
        case .modelNotFound(let id):
            return "Model '\(id)' not found in gateway config."
        }
    }
}

/// Response from /v1/models endpoint.
struct GatewayModelsResponse: Decodable {
    let data: [GatewayModel]
}

/// A single model from the gateway.
public struct GatewayModel: Decodable, Sendable {
    public let id: String
    public let name: String?
}

/// Response from /v1/agents endpoint.
struct GatewayAgentsResponse: Decodable {
    let data: [GatewayAgent]
}

/// A single agent from the gateway.
public struct GatewayAgent: Decodable, Sendable {
    public let id: String
    public let name: String
    public let alias: String?
}
