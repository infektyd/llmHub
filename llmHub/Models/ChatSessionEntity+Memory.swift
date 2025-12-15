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
    /// Call on deactivation, archival, or deletion.
    /// - Parameters:
    ///   - distillationService: The distillation service.
    ///   - modelContext: The SwiftData model context.
    func triggerDistillation(
        distillationService: ConversationDistillationService,
        modelContext: ModelContext
    ) {
        // Skip if too few messages (minimum for meaningful distillation)
        guard messages.count >= 3 else {
            logger.debug("Session \(self.id): skipping distillation (< 3 messages)")
            return
        }

        logger.info("Session \(self.id): scheduling distillation (\(self.messages.count) messages)")

        // Snapshot the data so distillation can proceed even if the session is deleted.
        let sessionID = self.id
        let providerID = self.providerID
        let snapshotMessages = self.messages
            .sorted { $0.createdAt < $1.createdAt }
            .map { $0.asDomain() }

        Task { @MainActor in
            await distillationService.distill(
                sessionID: sessionID,
                providerID: providerID,
                messages: snapshotMessages,
                modelContext: modelContext
            )
        }
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

