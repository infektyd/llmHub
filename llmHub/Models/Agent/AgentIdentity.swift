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

/// Registry of known agent identities.
/// Agents may override these dynamically later via discovery metadata.
enum AgentIdentityRegistry {

    /// Look up an agent's visual identity by ID.
    /// Falls back to a generic "Agent" identity for unknown IDs.
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

        // Fallback for unknown agents — still look up identity by ID pattern
        if let identity = defaults.first(where: { $0.id == agentID }) {
            return identity
        }

        return AgentIdentity(
            id: agentID,
            name: agentID.capitalized,
            emoji: "🤖",
            color: brandColor(for: agentID),
            roleDescription: ""
        )
    }

    /// Generate a brand color for an agent ID.
    /// Uses a hash of the ID to produce a consistent color even for unknown agents.
    static func brandColor(for agentID: String) -> Color {
        if let hex = brandColorHexs[agentID] {
            return Color(hex: hex)
        }
        // Deterministic fallback color based on ID hash
        let hash = agentID.hashValue
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.5, brightness: 0.8)
    }

    // MARK: - Default agent identities

    static let defaults: [AgentIdentity] = {
        [
            AgentIdentity(id: "syntra", name: "Syntra", emoji: "🟢", color: Color(hex: "#4CAF50"), roleDescription: "Coordinator"),
            AgentIdentity(id: "forge", name: "Forge", emoji: "🔨", color: Color(hex: "#FF6B35"), roleDescription: "Developer"),
            AgentIdentity(id: "recon", name: "Recon", emoji: "🔍", color: Color(hex: "#9C27B0"), roleDescription: "Researcher"),
            AgentIdentity(id: "pulse", name: "Pulse", emoji: "💓", color: Color(hex: "#FF69B4"), roleDescription: "Heartbeat")
        ]
    }()

    private static let brandColorHexs: [String: String] = [
        "syntra": "#4CAF50",
        "forge": "#FF6B35",
        "recon": "#9C27B0",
        "pulse": "#FF69B4"
    ]
}
