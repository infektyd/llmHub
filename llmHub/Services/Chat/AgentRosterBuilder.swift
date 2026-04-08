//
//  AgentRosterBuilder.swift
//  llmHub
//
//  Builds system context for multi-agent awareness.

import Foundation

/// Builds the agent roster system message injected into group chat requests.
enum AgentRosterBuilder {
    /// Generates a system message informing the agent about the group chat context.
    /// - Parameters:
    ///   - agentName: The name of the target agent.
    ///   - otherAgentIDs: IDs of the other active agents in this turn.
    /// - Returns: A system message string describing the multi-agent context.
    static func systemMessage(agentName: String, otherAgentIDs: [String]) -> String {
        let others = otherAgentIDs.joined(separator: ", ")
        return """
            This is a multi-agent conversation. You are \(agentName).
            Other active agents in this conversation: \(others).
            Respond with your expertise in mind. Coordinate rather than duplicate.
            If another agent covers your domain, acknowledge and defer.
            """
    }
}
