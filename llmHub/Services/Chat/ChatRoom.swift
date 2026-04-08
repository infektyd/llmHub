//
//  ChatRoom.swift
//  llmHub
//
//  Actor managing a single group-chat room: agents, message history, and response streaming.
//

import Foundation
import OSLog

// MARK: - Shared Types Crossing Actor Boundaries

/// An event emitted by a specific agent within a room.
nonisolated struct AgentResponse: Sendable {
    let agentID: String
    let event: GroupChatEvent
}

/// Group-chat-specific events beyond standard `ProviderEvent`.
nonisolated enum GroupChatEvent: Sendable {
    case token(agentID: String, text: String)
    case thinking(agentID: String, thought: String)
    case toolUse(agentID: String, id: String, name: String, input: String)
    case usage(agentID: String, usage: TokenUsage, costUSD: Double)
    case completion(agentID: String, message: ChatMessage)
    case truncated(agentID: String, message: ChatMessage)
    case error(agentID: String, error: LLMProviderError)
    case agentFinished(agentID: String)
    case agentStopped(agentID: String, reason: AgentStopReason)
    /// A room-level lifecycle event.
    case room(RoomEvent)
}

/// Room-level lifecycle events.
nonisolated enum RoomEvent: Sendable {
    case agentJoined(agentID: String)
    case agentLeft(agentID: String, reason: String)
    case roomCreated
    case roomClosed
}

// MARK: - ChatRoom Actor

/// Actor managing a single group chat room.
actor ChatRoom {
    let id: UUID
    var name: String
    private(set) var participants: [Agent] = []

    private var messageHistory: [ChatMessage] = []
    private var responseStreams: [String: AsyncStream<AgentResponse>.Continuation] = [:]
    private var eventContinuation: AsyncStream<GroupChatEvent>.Continuation?
    private var eventStreamFinished = false

    /// Agent sessions keyed by agent ID.
    private var agentSessions: [String: AgentSession] = [:]

    private let logger = Logger(subsystem: "com.llmhub", category: "ChatRoom")

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    // MARK: - Agent Management

    func addAgent(_ agent: Agent) {
        guard !participants.contains(where: { $0.id == agent.id }) else { return }
        participants.append(agent)
        logger.info("Agent \(agent.name) (\(agent.id)) joined room \(self.id.uuidString)")
        _broadcast(.room(.agentJoined(agentID: agent.id)))
    }

    func removeAgent(agentID: String, reason: String) async {
        participants.removeAll { $0.id == agentID }
        if let session = agentSessions.removeValue(forKey: agentID) {
            await session.cancel()
        }
        responseStreams[agentID]?.finish()
        responseStreams.removeValue(forKey: agentID)
        _broadcast(.room(.agentLeft(agentID: agentID, reason: reason)))
    }

    func participantIDs() -> [String] {
        participants.map(\.id)
    }

    func participantsList() -> [Agent] {
        participants
    }

    // MARK: - Message History

    func addMessage(_ message: ChatMessage) {
        messageHistory.append(message)
        _broadcastRoomMessage(message)
    }

    func history() -> [ChatMessage] {
        messageHistory
    }

    // MARK: - Message Routing

    /// Result of routing a message to determine which agents should respond.
    nonisolated struct RoutingResult: Sendable {
        /// Agents that should generate a response.
        let targetAgents: [Agent]
        /// Whether this was an explicit @mention or a broadcast.
        let isExplicitMention: Bool
    }

    /// Determines which agents should respond to a message based on @mentions.
    /// - If the message contains @agent mentions, only those agents respond.
    /// - If no @mentions, all participants respond (broadcast).
    func routeMessage(_ message: ChatMessage) -> RoutingResult {
        let content = message.content.lowercased()
        var mentioned: [Agent] = []

        for agent in participants {
            if content.contains("@" + agent.id.lowercased())
                || content.contains("@" + agent.name.lowercased()) {
                mentioned.append(agent)
            }
        }

        if !mentioned.isEmpty {
            return RoutingResult(targetAgents: mentioned, isExplicitMention: true)
        }

        // No explicit mentions — broadcast to all participants.
        return RoutingResult(targetAgents: participants, isExplicitMention: false)
    }

    // MARK: - Agent Response Streams

    /// Returns an AsyncStream of AgentResponse events for a given agent.
    func responseStream(for agentID: String) -> AsyncStream<AgentResponse> {
        AsyncStream { continuation in
            self._registerContinuation(for: agentID, continuation: continuation)
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?._removeResponseStream(for: agentID)
                }
            }
        }
    }

    /// Yields an event for a specific agent into the room's unified event stream.
    func broadcastEvent(_ event: GroupChatEvent) {
        _broadcast(event)
    }

    // MARK: - Unified Room Event Stream

    /// A unified stream of all group-chat events (agent responses + room lifecycle).
    var eventStream: AsyncStream<GroupChatEvent> {
        AsyncStream { continuation in
            self._setEventContinuation(continuation)
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?._closeEventStream()
                }
            }
        }
    }

    // MARK: - AgentSession (per-agent state machine)

    func session(for agentID: String) -> AgentSession {
        if let existing = agentSessions[agentID] {
            return existing
        }
        let session = AgentSession(agentID: agentID)
        agentSessions[agentID] = session
        return session
    }

    func cancelSession(for agentID: String) async {
        if let s = agentSessions.removeValue(forKey: agentID) {
            await s.cancel()
        }
    }

    // MARK: - Cost Tracking

    /// Returns a cost snapshot for a specific agent.
    func costSnapshot(for agentID: String) async -> AgentCostSnapshot? {
        guard let session = agentSessions[agentID] else { return nil }
        return await session.costSnapshot()
    }

    /// Returns a room-level total cost snapshot across all agents.
    func roomCostSnapshot() async -> AgentCostSnapshot {
        var inputTokens = 0
        var outputTokens = 0
        var cachedTokens = 0
        var totalCostUSD: Double = 0

        for session in agentSessions.values {
            let snap = await session.costSnapshot()
            inputTokens += snap.inputTokens
            outputTokens += snap.outputTokens
            cachedTokens += snap.cachedTokens
            totalCostUSD += snap.totalCostUSD
        }

        return AgentCostSnapshot(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedTokens: cachedTokens,
            totalCostUSD: totalCostUSD
        )
    }

    // MARK: - Cleanup

    func close() async {
        for agentID in agentSessions.keys {
            await cancelSession(for: agentID)
        }
        for cont in responseStreams.values {
            cont.finish()
        }
        responseStreams.removeAll()
        _broadcast(.room(.roomClosed))
        await _closeEventStream()
    }

    // MARK: - Private helpers (all actor-isolated)

    private func _registerContinuation(
        for agentID: String, continuation: AsyncStream<AgentResponse>.Continuation
    ) {
        responseStreams[agentID] = continuation
    }

    private func _removeResponseStream(for agentID: String) {
        responseStreams.removeValue(forKey: agentID)
    }

    private func _broadcast(_ event: GroupChatEvent) {
        guard !eventStreamFinished else { return }
        eventContinuation?.yield(event)
    }

    private func _broadcastRoomMessage(_ message: ChatMessage) {
        if message.role == .assistant, let senderAgent = message.senderAgentID {
            _broadcast(.completion(agentID: senderAgent, message: message))
        }
    }

    private func _setEventContinuation(_ continuation: AsyncStream<GroupChatEvent>.Continuation) {
        eventContinuation = continuation
    }

    private func _closeEventStream() async {
        eventStreamFinished = true
        eventContinuation?.finish()
        eventContinuation = nil
    }
}

// MARK: - AgentCostTracking

/// Per-agent cost tracking state (Sendable, safe to cross actor boundaries).
nonisolated struct AgentCostSnapshot: Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let totalCostUSD: Double
}

// MARK: - AgentSession Actor

/// Per-agent session state machine within a ChatRoom.
actor AgentSession {
    let agentID: String
    private(set) var state: AgentSessionState = .created
    private(set) var accumulatedResponse: String = ""

    /// Isolated tool session for this agent (persistent cache, shell sessions).
    let toolSession: ToolSession

    /// Accumulated token usage for this agent.
    private var totalInputTokens: Int = 0
    private var totalOutputTokens: Int = 0
    private var totalCachedTokens: Int = 0
    private var totalCostUSD: Double = 0

    init(agentID: String, toolSession: ToolSession? = nil) {
        self.agentID = agentID
        self.toolSession = toolSession ?? ToolSession()
    }

    func beginProcessing() {
        state = .processing
        accumulatedResponse = ""
    }

    func appendResponse(_ text: String) {
        accumulatedResponse += text
    }

    func markIdle() {
        state = .idle
    }

    func markError(_ error: Error) {
        state = .error(error.localizedDescription)
    }

    func cancel() {
        state = .cancelled
    }

    func response() -> String {
        accumulatedResponse
    }

    func canReceiveMessage() -> Bool {
        state.canReceive
    }

    // MARK: - Cost Tracking

    func recordUsage(inputTokens: Int, outputTokens: Int, cachedTokens: Int, costUSD: Double) {
        totalInputTokens += inputTokens
        totalOutputTokens += outputTokens
        totalCachedTokens += cachedTokens
        totalCostUSD += costUSD
    }

    func costSnapshot() -> AgentCostSnapshot {
        AgentCostSnapshot(
            inputTokens: totalInputTokens,
            outputTokens: totalOutputTokens,
            cachedTokens: totalCachedTokens,
            totalCostUSD: totalCostUSD
        )
    }
}

// MARK: - AgentSessionState

nonisolated enum AgentSessionState: Sendable {
    case created
    case processing
    case idle
    case error(String)
    case cancelled

    var canReceive: Bool {
        switch self {
        case .created, .idle:
            return true
        case .processing, .error, .cancelled:
            return false
        }
    }
}
