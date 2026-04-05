//
//  ChatRoomCoordinator.swift
//  llmHub
//
//  Created for llmHub v2 Multi-Agent Group Chat.
//

import Foundation
import OSLog
import SwiftData

// MARK: - Coordinator Errors

nonisolated enum CoordinatorError: Error, Sendable {
    case roomNotFound
    case agentNotFound(agentID: String)
    case roomAlreadyExists(roomID: UUID)
    case invalidSession
}

// MARK: - ChatRoomCoordinator Actor

/// Top-level actor managing multiple `ChatRoom` instances, routing messages between
/// the UI layer and agent sessions, and maintaining the lifecycle of group chat rooms.
actor ChatRoomCoordinator {
    private var activeRooms: [UUID: ChatRoom] = [:]
    private let logger = Logger(subsystem: "com.llmhub", category: "ChatRoomCoordinator")

    init() {}

    // MARK: - Room Lifecycle

    /// Creates a new `ChatRoom` and returns its identifier.
    func createRoom(id: UUID = UUID(), name: String) -> UUID {
        if activeRooms[id] != nil {
            // Already exists, return existing ID (idempotent).
            return id
        }
        let room = ChatRoom(id: id, name: name)
        activeRooms[id] = room
        logger.info("Created room '\(name)' (id=\(id.uuidString))")
        return id
    }

    /// Closes and removes a room, cancelling all its agent streams.
    func closeRoom(roomID: UUID) async {
        guard let room = activeRooms.removeValue(forKey: roomID) else {
            logger.warning("Attempted to close nonexistent room \(roomID.uuidString)")
            return
        }
        await room.close()
        logger.info("Closed room \(roomID.uuidString)")
    }

    /// Returns the number of active rooms (for diagnostics).
    func activeRoomCount() -> Int {
        activeRooms.count
    }

    // MARK: - Agent Management

    /// Adds an agent to a room.
    func addAgent(to roomID: UUID, agent: Agent) async throws {
        guard let room = activeRooms[roomID] else {
            throw CoordinatorError.roomNotFound
        }
        await room.addAgent(agent)
        logger.info("Added agent \(agent.name) to room \(roomID.uuidString)")
    }

    /// Removes an agent from a room.
    func removeAgent(from roomID: UUID, agentID: String, reason: String = "removed") async throws {
        guard let room = activeRooms[roomID] else {
            throw CoordinatorError.roomNotFound
        }
        await room.removeAgent(agentID: agentID, reason: reason)
    }

    /// Returns the current agents in a room.
    func agentsInRoom(_ roomID: UUID) async throws -> [Agent] {
        guard let room = activeRooms[roomID] else {
            throw CoordinatorError.roomNotFound
        }
        return await room.participantsList()
    }

    // MARK: - Message Routing

    /// Routes a message into the specified room. The room adds it to
    /// history and notifies its observers.
    func sendMessage(to roomID: UUID, message: ChatMessage) async throws {
        guard let room = activeRooms[roomID] else {
            throw CoordinatorError.roomNotFound
        }
        await room.addMessage(message)
        logger.debug("Message routed to room \(roomID.uuidString)")
    }

    // MARK: - Response Stream Wiring

    /// Returns an `AsyncStream<AgentResponse>` for a specific agent in a room.
    /// The caller (e.g. ViewModel) iterates this to receive typed peragent updates.
    func responseStreamForAgent(
        in roomID: UUID,
        for agentID: String
    ) async -> AsyncStream<AgentResponse>? {
        guard let room = activeRooms[roomID] else { return nil }
        return await room.responseStream(for: agentID)
    }

    /// Broadcasts a `GroupChatEvent` on behalf of an agent into the room.
    func broadcastEvent(to roomID: UUID, event: GroupChatEvent) async throws {
        guard let room = activeRooms[roomID] else {
            throw CoordinatorError.roomNotFound
        }
        await room.broadcastEvent(event)
    }

    // MARK: - Event Subscription

    /// Subscribes to a room's `AsyncStream<GroupChatEvent>` for UI observation.
    func subscribeToRoom(_ roomID: UUID) async -> AsyncStream<GroupChatEvent>? {
        guard let room = activeRooms[roomID] else {
            logger.warning("Cannot subscribe to nonexistent room \(roomID.uuidString)")
            return nil
        }
        return await room.eventStream
    }

    // MARK: - History Access

    /// Returns the message history for a room.
    func roomMessages(_ roomID: UUID) async -> [ChatMessage]? {
        guard let room = activeRooms[roomID] else { return nil }
        return await room.history()
    }

    // MARK: - Cost Tracking

    /// Returns a cost snapshot for a specific agent in a room.
    func costSnapshot(for agentID: String, in roomID: UUID) async -> AgentCostSnapshot? {
        guard let room = activeRooms[roomID] else { return nil }
        return await room.costSnapshot(for: agentID)
    }

    /// Returns a room-level total cost snapshot across all agents.
    func roomCostSnapshot(_ roomID: UUID) async -> AgentCostSnapshot? {
        guard let room = activeRooms[roomID] else { return nil }
        return await room.roomCostSnapshot()
    }

    // MARK: - Cleanup

    /// Closes all active rooms.
    func closeAll() async {
        let rooms = activeRooms.values
        activeRooms.removeAll()
        for room in rooms {
            await room.close()
        }
        logger.info("Closed all rooms (count=\(rooms.count))")
    }
}
