//
//  SessionEndReason.swift
//  llmHub
//
//  Created by Agent on 2026-01-07.
//

import Foundation

/// Explicit reason for why a session was ended/transitioned.
///
/// This is used to guard background work (notably memory distillation) so that explicit user deletion
/// never triggers network sidecar work or any memory artifacts.
enum SessionEndReason: Sendable, Equatable {
    /// User explicitly deleted the session/conversation.
    case userDeleted
    /// User explicitly archived the session/conversation.
    case userArchived

    // Future-proofing hooks (not currently scheduled for distillation).
    case normalClose
    case appLifecycleEnded
    case inactivityTimeout
}

