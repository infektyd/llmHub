//
//  ConversationDistillationScheduling.swift
//  llmHub
//
//  Created by Agent on 2026-01-07.
//

import Foundation
import SwiftData

/// Scheduling abstraction for conversation distillation.
///
/// This exists to:
/// - enforce hard guards (e.g. never distill on explicit user deletion)
/// - debounce + dedupe distillation work
/// - support safe cancellation on deletion
@MainActor
protocol ConversationDistillationScheduling: AnyObject {
    func scheduleDistillation(
        sessionID: UUID,
        providerID: String,
        messages: [ChatMessage],
        modelContext: ModelContext,
        reason: SessionEndReason
    )

    func cancelDistillation(sessionID: UUID)
    func cancelDistillation(sessionIDs: [UUID])
}

