//
//  MessageProvenance.swift
//  llmHub
//

import Foundation

/// Identifies whether some output is eligible to influence chat memory/prompting.
///
/// Contract:
/// - `.chat` may be persisted/reused for future chat generations.
/// - `.sidecar` MUST be treated as ephemeral only (UI artifacts/logs) and must not
///   be persisted into chat memory or included in chat prompting.
public nonisolated struct MessageProvenance: Codable, Equatable, Sendable {

    public nonisolated enum Channel: String, Codable, Equatable, Sendable {
        case chat
        case sidecar
        case agent
    }

    public var channel: Channel
    public var model: String?
    public var agentID: String?
    public var agentName: String?

    public static let chat = MessageProvenance(channel: .chat, model: nil, agentID: nil, agentName: nil)

    public static func sidecar(model: String) -> MessageProvenance {
        MessageProvenance(channel: .sidecar, model: model, agentID: nil, agentName: nil)
    }

    public static func agent(id: String, name: String, model: String? = nil) -> MessageProvenance {
        MessageProvenance(channel: .agent, model: model, agentID: id, agentName: name)
    }

    public init(channel: Channel, model: String?, agentID: String? = nil, agentName: String? = nil) {
        self.channel = channel
        self.model = model
        self.agentID = agentID
        self.agentName = agentName
    }
}
