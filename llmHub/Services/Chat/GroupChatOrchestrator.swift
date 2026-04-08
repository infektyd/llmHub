//
//  GroupChatOrchestrator.swift
//  llmHub
//
//  Concurrent multi-agent streaming for group chat.
//  Extracted to avoid @MainActor isolation issues in ChatViewModel.
//

import Foundation
import OSLog
import SwiftData
import SwiftUI

/// Orchestrates concurrent streaming from multiple agents in a group chat.
/// Runs each agent stream in parallel (up to 4), updating UI on MainActor.
nonisolated final class GroupChatOrchestrator {
    private let logger = Logger(subsystem: "com.llmhub", category: "GroupChat")

    /// Updates UI state from off-MainActor context.
    typealias StateUpdater = @MainActor @Sendable (AgentResponseState) -> Void
    /// Checks if all agents are done and finalizes the group chat.
    typealias OnAllComplete = @MainActor @Sendable () -> Void

    /// Starts concurrent streaming from multiple agents.
    /// - Parameter stateUpdater: Closure to update per-agent UI state (runs on MainActor).
    /// - Parameter onAllComplete: Called when all agents reach terminal state (runs on MainActor).
    func startStreaming(
        agents: [Agent],
        messageText: String,
        contextId: String,
        generationID: UUID,
        session: ChatSessionEntity,
        modelContext: ModelContext,
        stateUpdater: @escaping StateUpdater,
        onAllComplete: @escaping OnAllComplete
    ) -> [Task<Void, Never>] {
        let cappedAgents = Array(agents.prefix(4))
        let persistenceBox = PersistenceBox(session: session, modelContext: modelContext)

        let allAgentIDs = cappedAgents.map { $0.id }

        return cappedAgents.enumerated().map { (index, agent) -> Task<Void, Never> in
            // Each agent needs the list of OTHER agents (excluding itself)
            let otherAgentIDs = allAgentIDs.filter { $0 != agent.id }

            return Task {
                // Hop to MainActor to initialize routing service and stream
                let (initialState, stream) = await MainActor.run {
                    let routingService = AgentRoutingService()
                    var state = AgentResponseState(
                        agentId: agent.id,
                        contextId: contextId,
                        orderIndex: index,
                        status: .thinking
                    )
                    state.startedAt = Date()
                    let sessionKey = "agent:\(agent.id):main"
                    let s = routingService.streamAgentSession(
                        agentID: agent.id,
                        sessionKey: sessionKey,
                        message: messageText,
                        history: [],
                        otherAgentIDs: otherAgentIDs,
                        groupContextId: contextId,
                        agentName: agent.name
                    )
                    return (state, s)
                }

                await streamAgentEvents(
                    initialState: initialState,
                    agentId: agent.id,
                    agentName: agent.name,
                    stream: stream,
                    generationID: generationID,
                    persistenceBox: persistenceBox,
                    stateUpdater: stateUpdater,
                    onAllComplete: onAllComplete
                )
            }
        }
    }
}

/// Streams agent responses off-MainActor, dispatching @MainActor callbacks.
private func streamAgentEvents(
    initialState: AgentResponseState,
    agentId: String,
    agentName: String,
    stream: AsyncThrowingStream<ProviderEvent, Error>,
    generationID: UUID,
    persistenceBox: PersistenceBox,
    stateUpdater: @escaping GroupChatOrchestrator.StateUpdater,
    onAllComplete: @escaping GroupChatOrchestrator.OnAllComplete
) async {
    var state = initialState
    let logger = Logger(subsystem: "com.llmhub", category: "GroupChat")

    func persistMessage(_ message: ChatMessage) {
        var tagged = message
        tagged.senderAgentID = agentId
        tagged.generationID = generationID
        let entity = ChatMessageEntity(message: tagged)
        entity.session = persistenceBox.session
        persistenceBox.modelContext.insert(entity)
        persistenceBox.session.updatedAt = Date()
        try? persistenceBox.modelContext.save()
    }

    func notifyComplete() async {
        await MainActor.run {
            stateUpdater(state)
            onAllComplete()
        }
    }

    do {
        for try await event in stream {
            try Task.checkCancellation()
            switch event {
            case .token(let text):
                state.content += text
                if case .thinking = state.status {
                    state.status = .streaming
                }
                await MainActor.run { stateUpdater(state) }

            case .completion(let message):
                state.status = .complete
                state.completedAt = Date()
                state.content = message.content
                persistMessage(message)
                await notifyComplete()

            case .truncated(let message):
                state.status = .complete
                state.completedAt = Date()
                state.content = message.content
                persistMessage(message)
                await notifyComplete()
                logger.warning("🔵 [GroupChat] Agent \(agentId) response truncated")

            case .error(let error):
                state.status = .error(error.localizedDescription)
                state.completedAt = Date()
                persistMessage(ChatMessage(
                    role: .assistant,
                    content: "Error from \(agentName): \(error.localizedDescription)",
                    parts: [.text("Error from \(agentName): \(error.localizedDescription)")],
                    senderAgentID: agentId
                ))
                await notifyComplete()
                logger.error("🔵 [GroupChat] Agent \(agentId) error: \(error.localizedDescription)")

            default:
                break
            }
        }
    } catch {
        if error is CancellationError {
            // Normal cancellation
        } else {
            state.status = .error(error.localizedDescription)
            state.completedAt = Date()
            persistMessage(ChatMessage(
                role: .assistant,
                content: "Error from \(agentName): \(error.localizedDescription)",
                parts: [.text("Error from \(agentName): \(error.localizedDescription)")],
                senderAgentID: agentId
            ))
            await notifyComplete()
            logger.error("🔵 [GroupChat] Agent \(agentId) stream error: \(error.localizedDescription)")
        }
    }
}

// MARK: - PersistenceBox

/// Wraps non-Sendable SwiftData types so they can be captured in Task closures.
private struct PersistenceBox: @unchecked Sendable {
    nonisolated(unsafe) let session: ChatSessionEntity
    nonisolated(unsafe) let modelContext: ModelContext
}
