//
//  AgentStopReason.swift
//  llmHub
//

import Foundation

/// Distinct reasons why an agent/tool loop stopped without producing a normal completion.
enum AgentStopReason: Equatable, Sendable {
    /// The agent reached the per-run iteration cap.
    case iterationLimitReached(limit: Int, used: Int)
}
