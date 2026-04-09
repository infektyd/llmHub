//
//  AgentIdentity.swift
//  llmHub
//
//  Visual identity configuration for agents in multi-agent chat.
//  Maps agent IDs to brand colors, emojis, and display names.
//

import SwiftUI

/// Visual identity for an agent in the transcript UI.
nonisolated struct AgentIdentity: Equatable, Sendable {
    let id: String
    let name: String
    let emoji: String
    let color: Color
    let roleDescription: String
}

/// Registry of agent identities.
/// Agents are discovered dynamically from the OpenClaw gateway at runtime.
/// This registry resolves visual identity from discovered agent metadata,
/// falling back to deterministic colors for any unknown agent ID.
enum AgentIdentityRegistry {

    /// Look up an agent's visual identity by ID.
    /// Checks discovered agents first, then falls back to a generic identity
    /// with a deterministic color based on the agent ID hash.
    static func lookup(_ agentID: String, knownAgents: [Agent]?) -> AgentIdentity {
        // Check known agents discovered via OpenClaw
        if let agents = knownAgents, let match = agents.first(where: { $0.id == agentID }) {
            return AgentIdentity(
                id: match.id,
                name: match.name,
                emoji: match.emoji,
                color: brandColor(for: agentID),
                roleDescription: ""
            )
        }

        return AgentIdentity(
            id: agentID,
            name: agentID.capitalized,
            emoji: "🤖",
            color: brandColor(for: agentID),
            roleDescription: ""
        )
    }

    /// Generate a deterministic brand color for an agent ID.
    /// Produces a consistent hue based on the ID hash so each agent
    /// always gets the same color even without explicit configuration.
    static func brandColor(for agentID: String) -> Color {
        let hash = agentID.hashValue
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.5, brightness: 0.8)
    }
}
