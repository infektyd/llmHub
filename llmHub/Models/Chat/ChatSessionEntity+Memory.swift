//
//  ChatSessionEntity+Memory.swift
//  llmHub
//
//  Created by Agent on 12/15/25.
//

import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.llmhub", category: "SessionMemory")

// MARK: - Memory Lifecycle Integration

@MainActor
extension ChatSessionEntity {

    /// Triggers conversation distillation in background.
    /// Call on explicit user archival only.
    /// - Parameters:
    ///   - distillationScheduler: The distillation scheduler (debounce + dedupe + cancellation + guards).
    ///   - modelContext: The SwiftData model context.
    ///   - reason: The explicit reason for ending/transitioning the session.
    func triggerDistillation(
        distillationScheduler: ConversationDistillationScheduling = ConversationDistillationScheduler.shared,
        modelContext: ModelContext,
        reason: SessionEndReason
    ) {
        // Snapshot the data so scheduling is stable even if session state changes after the call.
        let sessionID = id
        let providerID = self.providerID
        let snapshotMessages = messages
            .sorted { $0.createdAt < $1.createdAt }
            .map { $0.asDomain() }

        // Skip if too few messages (minimum for meaningful distillation).
        guard snapshotMessages.count >= 3 else {
            logger.debug("Session \(sessionID): skipping distillation (< 3 messages, reason=\(String(describing: reason)))")
            return
        }

        logger.info(
            "Session \(sessionID): distillation request (reason=\(String(describing: reason)), messages=\(snapshotMessages.count))"
        )

        distillationScheduler.scheduleDistillation(
            sessionID: sessionID,
            providerID: providerID,
            messages: snapshotMessages,
            modelContext: modelContext,
            reason: reason
        )
    }

    /// Checks if this session has been distilled into a memory.
    /// - Parameter modelContext: The SwiftData model context.
    /// - Returns: True if a memory exists for this session.
    func hasBeenDistilled(modelContext: ModelContext) -> Bool {
        let sessionID = self.id
        do {
            let count = try modelContext.fetchCount(
                FetchDescriptor<MemoryEntity>(
                    predicate: #Predicate { $0.sourceSessionID == sessionID }
                )
            )
            return count > 0
        } catch {
            logger.error("Failed to check distillation status: \(error.localizedDescription)")
            return false
        }
    }
}
