//
//  AgentRoutingService.swift
//  llmHub
//
//  Service for routing messages to OpenClaw agents via dedicated sessions_send requests.
//

import Foundation
import OSLog

/// Routes messages to specific agents using the OpenClaw gateway's session API.
///
/// When the user @mentions an agent (e.g., `@forge`), this service constructs the
/// correct session key and routes the message directly to that agent, bypassing the
/// default agent routing bug where the gateway only delivers to the first mentioned agent.
@MainActor
final class AgentRoutingService {
    private let baseURL: URL
    private let logger = Logger(subsystem: "com.llmHub", category: "AgentRoutingService")

    init(baseURL: URL = URL(string: "http://localhost:18789/v1")!) {
        self.baseURL = baseURL
    }

    // MARK: - Agent Response Streaming

    /// Streams a response from a specific agent in a session.
    ///
    /// This method opens a dedicated session to the target agent and streams
    /// the response back, tagging each event with the agent's ID.
    ///
    /// - Parameters:
    ///   - agentID: The agent ID to route to (e.g., "forge").
    ///   - sessionKey: The session key to use (e.g., "agent:forge:main").
    ///   - message: The user message content.
    ///   - history: Prior conversation messages, if any.
    /// - Returns: An async throwing stream of ProviderEvent tagged with agentID.
    func streamAgentSession(
        agentID: String,
        sessionKey: String,
        message: String,
        history: [ChatMessage] = []
    ) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    logger.info(
                        "🔵 [AgentRouter] Routing to agent: \(agentID) sessionKey: \(sessionKey)"
                    )

                    // Build a sessions_send request
                    let endpoint = baseURL.appendingPathComponent("sessions.send")

                    let payload: [String: Any] = [
                        "sessionKey": sessionKey,
                        "content": message,
                    ]

                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.addValue("Bearer 3d0f30ebdb793f1d86523ea3f2ecc52615435a3874810790", forHTTPHeaderField: "Authorization")
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (result, response) = try await LLMURLSession.bytes(for: request)

                    guard let http = response as? HTTPURLResponse,
                        (200...299).contains(http.statusCode)
                    else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        var errorBody = ""
                        for try await line in result.lines { errorBody += line }
                        logger.error(
                            "🔴 [AgentRouter] sessions_send failed for \(agentID): HTTP \(statusCode) body: \(errorBody)"
                        )
                        continuation.yield(
                            .error(.server(reason: "Gateway error for \(agentID) (HTTP \(statusCode))"))
                        )
                        continuation.finish()
                        return
                    }

                    // Parse SSE lines from sessions_send response
                    var fullText = ""
                    for try await line in result.lines {
                        try Task.checkCancellation()
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data: ") else { continue }
                        let jsonStr = String(trimmed.dropFirst(6))
                        if jsonStr == "[DONE]" { break }

                        guard let data = jsonStr.data(using: .utf8),
                            let chunk = try? JSONDecoder().decode(XAIChatStreamChunk.self, from: data),
                            let choice = chunk.choices.first
                        else { continue }

                        if let content = choice.delta.content {
                            fullText += content
                            continuation.yield(.token(text: content))
                        }

                        if choice.finish_reason == "stop" || choice.finish_reason == "length" {
                            let message = ChatMessage(
                                id: UUID(),
                                role: .assistant,
                                content: fullText,
                                parts: [.text(fullText)],
                                createdAt: Date(),
                                codeBlocks: [],
                                tokenUsage: chunk.usage.map {
                                    TokenUsage(
                                        inputTokens: $0.prompt_tokens,
                                        outputTokens: $0.completion_tokens,
                                        cachedTokens: 0
                                    )
                                },
                                senderAgentID: agentID
                            )
                            if choice.finish_reason == "length" {
                                continuation.yield(.truncated(message: message))
                            } else {
                                continuation.yield(.completion(message: message))
                            }
                        }

                        if let usage = chunk.usage {
                            continuation.yield(
                                .usage(
                                    TokenUsage(
                                        inputTokens: usage.prompt_tokens,
                                        outputTokens: usage.completion_tokens,
                                        cachedTokens: 0
                                    )
                                )
                            )
                        }
                    }

                    // If we streamed content but never hit a finish_reason, yield completion anyway
                    if !fullText.isEmpty {
                        let message = ChatMessage(
                            id: UUID(),
                            role: .assistant,
                            content: fullText,
                            parts: [.text(fullText)],
                            createdAt: Date(),
                            codeBlocks: [],
                            senderAgentID: agentID
                        )
                        continuation.yield(.completion(message: message))
                    }

                    continuation.finish()

                } catch {
                    if error is CancellationError {
                        continuation.finish()
                        return
                    }
                    logger.error("🔴 [AgentRouter] Stream error for \(agentID): \(error)")
                    continuation.yield(.error(.network(error as? URLError ?? URLError(.unknown))))
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
