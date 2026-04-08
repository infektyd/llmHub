//
//  MemoryServiceClient.swift
//  llmHub
//
//  HTTP client for the Sovereign Memory FastAPI service.
//  Provides pre-LLM recall and post-LLM conversation processing hooks.
//
//  Service: http://localhost:8901 (default)
//  Feature flag: AppSettings.sovereignMemoryEnabled
//

import Foundation
import OSLog

private let logger = AppLogger.category("SovereignMemory")

// MARK: - Configuration

/// Configuration for the Sovereign Memory service connection.
struct SovereignMemoryConfig: Sendable {
    /// Base URL of the FastAPI service.
    var baseURL: URL

    /// Timeout for recall calls (fail-fast to avoid blocking UX).
    var recallTimeoutSeconds: TimeInterval

    /// Timeout for learn/process calls (async, can be more generous).
    var writeTimeoutSeconds: TimeInterval

    static let `default` = SovereignMemoryConfig(
        baseURL: URL(string: "http://localhost:8901")!,
        recallTimeoutSeconds: 0.2,   // 200ms — fail fast
        writeTimeoutSeconds: 5.0     // 5s — fire-and-forget
    )
}

// MARK: - Request/Response Models

struct SovereignRecallRequest: Codable {
    let query: String
    let agent_id: String
    let thread_id: String?
    let limit: Int
    let format: String
    let include_learnings: Bool
    let budget_tokens: Int
}

struct SovereignRecallResponse: Codable {
    let status: String
    let agent_id: String
    let query: String
    let context: String
    let result_count: Int
    let latency_ms: Double
}

struct SovereignLearnRequest: Codable {
    let agent_id: String
    let content: String
    let category: String
    let confidence: Double
}

struct SovereignLearnResponse: Codable {
    let status: String
    let agent_id: String
    let learning_id: Int
    let latency_ms: Double
}

struct SovereignConversationMessage: Codable {
    let role: String
    let content: String
}

struct SovereignProcessRequest: Codable {
    let agent_id: String
    let thread_id: String?
    let messages: [SovereignConversationMessage]
    let extract_learnings: Bool
}

struct SovereignProcessResponse: Codable {
    let status: String
    let agent_id: String
    let events_logged: Int
    let learnings_extracted: Int
    let latency_ms: Double
}

struct SovereignHealthResponse: Codable {
    let status: String
    let version: String
    let db_path: String
    let db_exists: Bool
}

// MARK: - Sovereign Memory Client

/// HTTP client for the Sovereign Memory FastAPI service.
///
/// Usage:
/// ```swift
/// let client = SovereignMemoryClient()
///
/// // Pre-LLM: recall relevant memories
/// if let context = await client.recall(
///     query: userMessage,
///     agentID: "forge",
///     threadID: threadID
/// ) {
///     // Inject context into system prompt
/// }
///
/// // Post-LLM: log the conversation turn (fire-and-forget)
/// client.processConversation(
///     agentID: "forge",
///     userMessage: userMessage,
///     assistantResponse: response
/// )
/// ```
final class SovereignMemoryClient: Sendable {

    private let config: SovereignMemoryConfig
    private let session: URLSession

    init(config: SovereignMemoryConfig = .default) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = config.recallTimeoutSeconds
        cfg.timeoutIntervalForResource = config.writeTimeoutSeconds
        cfg.waitsForConnectivity = false  // localhost — don't wait for network
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - Recall (Pre-LLM, Synchronous)

    /// Query memories for a given agent/message. Called before LLM request.
    ///
    /// - Returns: Formatted context string ready for injection, or nil if no memories found or service unavailable.
    func recall(
        query: String,
        agentID: String,
        threadID: String? = nil,
        limit: Int = 5,
        budgetTokens: Int = 1200
    ) async -> String? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let request = SovereignRecallRequest(
            query: query,
            agent_id: agentID,
            thread_id: threadID,
            limit: limit,
            format: "markdown",
            include_learnings: true,
            budget_tokens: budgetTokens
        )

        do {
            let response: SovereignRecallResponse = try await post(
                path: "/recall",
                body: request,
                timeout: config.recallTimeoutSeconds
            )

            guard response.status == "ok",
                  !response.context.isEmpty,
                  response.result_count > 0 else {
                logger.debug("Sovereign recall: no results for agent=\(agentID)")
                return nil
            }

            logger.info(
                "Sovereign recall: \(response.result_count) results in \(Int(response.latency_ms))ms for agent=\(agentID)"
            )
            return response.context

        } catch {
            // Fail gracefully — don't block the user's experience
            logger.debug("Sovereign recall failed (service may be offline): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Learn (Direct)

    /// Store a learning directly.
    @discardableResult
    func learn(
        agentID: String,
        content: String,
        category: String = "general",
        confidence: Double = 1.0
    ) async -> Bool {
        let request = SovereignLearnRequest(
            agent_id: agentID,
            content: content,
            category: category,
            confidence: confidence
        )

        do {
            let response: SovereignLearnResponse = try await post(
                path: "/learn",
                body: request,
                timeout: config.writeTimeoutSeconds
            )
            logger.debug("Sovereign learn: stored #\(response.learning_id) in \(Int(response.latency_ms))ms")
            return response.status == "ok"
        } catch {
            logger.debug("Sovereign learn failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Process Conversation (Post-LLM, Fire-and-Forget)

    /// Log a conversation turn for episodic memory and learning extraction.
    /// This is fire-and-forget — errors are logged but not propagated.
    func processConversation(
        agentID: String,
        userMessage: String,
        assistantResponse: String,
        threadID: String? = nil,
        extractLearnings: Bool = true
    ) {
        let messages = [
            SovereignConversationMessage(role: "user", content: userMessage),
            SovereignConversationMessage(role: "assistant", content: assistantResponse)
        ]

        let request = SovereignProcessRequest(
            agent_id: agentID,
            thread_id: threadID,
            messages: messages,
            extract_learnings: extractLearnings
        )

        // Fire-and-forget — don't await
        Task {
            do {
                let response: SovereignProcessResponse = try await post(
                    path: "/process_conversation",
                    body: request,
                    timeout: config.writeTimeoutSeconds
                )
                logger.debug(
                    "Sovereign process: \(response.events_logged) events, \(response.learnings_extracted) learnings in \(Int(response.latency_ms))ms"
                )
            } catch {
                logger.debug("Sovereign process failed (non-blocking): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Health Check

    /// Check if the Sovereign Memory service is reachable.
    func healthCheck() async -> SovereignHealthResponse? {
        do {
            let response: SovereignHealthResponse = try await get(path: "/health")
            return response
        } catch {
            return nil
        }
    }

    // MARK: - Prompt Injection

    /// Wraps memory context in XML tags for system prompt injection.
    /// Returns nil if context is empty.
    static func formatForInjection(context: String) -> String? {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "<sovereign_memory>\n\(trimmed)\n</sovereign_memory>"
    }

    // MARK: - HTTP Helpers

    private func post<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request,
        timeout: TimeInterval
    ) async throws -> Response {
        let url = config.baseURL.appendingPathComponent(path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = timeout
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SovereignMemoryError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw SovereignMemoryError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func get<Response: Decodable>(
        path: String
    ) async throws -> Response {
        let url = config.baseURL.appendingPathComponent(path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = config.recallTimeoutSeconds

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SovereignMemoryError.invalidResponse
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }
}

// MARK: - Errors

enum SovereignMemoryError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Sovereign Memory service"
        case .httpError(let code, let body):
            return "Sovereign Memory HTTP \(code): \(body)"
        case .timeout:
            return "Sovereign Memory service timed out"
        }
    }
}
