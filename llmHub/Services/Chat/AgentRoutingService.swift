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
    private let manager: OpenClawManager
    private let logger = Logger(subsystem: "com.llmHub", category: "AgentRoutingService")

    init(baseURL: URL = URL(string: "http://localhost:18789/v1")!) {
        self.baseURL = baseURL
        self.manager = OpenClawManager(baseURL: baseURL)
    }

    // MARK: - Agent Response Streaming

    /// Streams a response from a specific agent using the chat/completions endpoint.
    ///
    /// Routes to the target agent via the `openclaw/<agentID>` model identifier,
    /// which the OpenClaw gateway resolves to the correct agent. Uses the standard
    /// streaming chat completions API (POST /v1/chat/completions) with SSE.
    ///
    /// - Parameters:
    ///   - agentID: The agent ID to route to (e.g., "forge").
    ///   - message: The user message content.
    ///   - history: Prior conversation messages to include as context.
    ///   - otherAgentIDs: IDs of other agents in this group chat turn (for roster injection).
    ///   - groupContextId: Shared ID tying all agents' responses to the same turn.
    ///   - agentName: Display name of the target agent (for roster context).
    /// - Returns: An async throwing stream of ProviderEvent tagged with agentID.
    func streamAgentSession(
        agentID: String,
        sessionKey: String,
        message: String,
        history: [ChatMessage] = [],
        otherAgentIDs: [String] = [],
        groupContextId: String? = nil,
        agentName: String? = nil
    ) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    logger.info(
                        "🔵 [AgentRouter] Routing to agent: \(agentID) via openclaw/\(agentID)"
                    )

                    // Build messages array: system context (roster) + history + current user message
                    var ocMessages: [XAIChatMessage] = []

                    // Inject agent roster system message for multi-agent awareness
                    if !otherAgentIDs.isEmpty, let agentName {
                        let rosterText = AgentRosterBuilder.systemMessage(
                            agentName: agentName,
                            otherAgentIDs: otherAgentIDs
                        )

                        ocMessages.append(XAIChatMessage(role: "system", content: rosterText))

                        if let groupContextId {
                            let contextNote = "This conversation turn is identified by \(groupContextId). The message below was sent to all agents simultaneously."
                            ocMessages.append(XAIChatMessage(role: "system", content: contextNote))
                        }
                    }

                    ocMessages.append(contentsOf: history.map { msg in
                        XAIChatMessage(role: msg.role.rawValue, content: msg.content)
                    })
                    ocMessages.append(XAIChatMessage(role: "user", content: message))

                    let request = try manager.makeChatRequest(
                        messages: ocMessages,
                        model: "openclaw/\(agentID)",
                        stream: true
                    )

                    let (result, response) = try await LLMURLSession.bytes(for: request)

                    guard let http = response as? HTTPURLResponse,
                        (200...299).contains(http.statusCode)
                    else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        var errorBody = ""
                        for try await line in result.lines { errorBody += line }
                        logger.error(
                            "🔴 [AgentRouter] chat/completions failed for \(agentID): HTTP \(statusCode) body: \(errorBody)"
                        )
                        continuation.yield(
                            .error(.server(reason: "Gateway error for \(agentID) (HTTP \(statusCode))"))
                        )
                        continuation.finish()
                        return
                    }

                    // Parse SSE streaming response from chat/completions
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
