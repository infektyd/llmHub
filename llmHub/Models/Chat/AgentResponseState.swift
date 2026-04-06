//
//  AgentResponseState.swift
//  llmHub
//
//  Tracks per-agent response state during concurrent multi-agent streaming.
//

import Foundation
import SwiftUI

/// Tracks the live state of a single agent's response during concurrent group chat streaming.
struct AgentResponseState: Identifiable, Equatable, Sendable {
    let id: String  // agentId, stable for this response
    let contextId: String  // Groups responses to the same user message
    let orderIndex: Int  // Position in the @mention order for display sorting

    enum Status: Equatable, CustomStringConvertible, Sendable {
        case queued
        case thinking  // Connection established, waiting for tokens
        case streaming  // Tokens arriving
        case complete
        case error(String)

        var description: String {
            switch self {
            case .queued: return "queued"
            case .thinking: return "thinking"
            case .streaming: return "streaming"
            case .complete: return "complete"
            case .error(let message): return "error: \(message)"
            }
        }
    }

    var status: Status
    var content: String
    var startedAt: Date?
    var completedAt: Date?

    init(
        agentId: String,
        contextId: String,
        orderIndex: Int,
        status: Status = .queued,
        content: String = ""
    ) {
        self.id = agentId
        self.contextId = contextId
        self.orderIndex = orderIndex
        self.status = status
        self.content = content
    }

    static func == (lhs: AgentResponseState, rhs: AgentResponseState) -> Bool {
        lhs.id == rhs.id
            && lhs.contextId == rhs.contextId
            && lhs.orderIndex == rhs.orderIndex
            && lhs.status == rhs.status
            && lhs.content == rhs.content
            && lhs.startedAt == rhs.startedAt
            && lhs.completedAt == rhs.completedAt
    }
}
