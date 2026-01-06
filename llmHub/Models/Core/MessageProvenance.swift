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
    }

    public var channel: Channel
    public var model: String?

    public static let chat = MessageProvenance(channel: .chat, model: nil)

    public static func sidecar(model: String) -> MessageProvenance {
        MessageProvenance(channel: .sidecar, model: model)
    }

    public init(channel: Channel, model: String?) {
        self.channel = channel
        self.model = model
    }
}
