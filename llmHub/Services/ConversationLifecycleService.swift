//
//  ConversationLifecycleService.swift
//  llmHub
//
//  Created by Agent on 12/15/25.
//

import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.llmhub", category: "LifecycleService")

/// Service for managing conversation lifecycle and cleanup flagging.
@MainActor
final class ConversationLifecycleService {

    private let distillationService = ConversationDistillationService()

    // MARK: - Staleness Configuration

    /// Days of inactivity before a quick question is flagged.
    static let quickQuestionStaleDays: Int = 3
    /// Days of inactivity before a conversation without artifacts is flagged.
    static let noArtifactsStaleDays: Int = 7
    /// Days of inactivity before an archived conversation becomes auto-delete candidate.
    static let archivedAutoDeleteDays: Int = 14

    // MARK: - Staleness Detection

    /// Flags stale conversations for cleanup based on staleness rules.
    /// - Parameter modelContext: The SwiftData model context.
    /// - Returns: The number of newly flagged conversations.
    @discardableResult
    func flagStaleConversations(modelContext: ModelContext) -> Int {
        let now = Date()
        var flaggedCount = 0

        do {
            // Fetch all non-archived, non-flagged conversations
            let descriptor = FetchDescriptor<ChatSessionEntity>(
                predicate: #Predicate<ChatSessionEntity> { session in
                    session.flaggedForCleanupAt == nil && !session.isArchived
                }
            )

            let sessions = try modelContext.fetch(descriptor)

            for session in sessions {
                if shouldFlag(session: session, now: now) {
                    session.flaggedForCleanupAt = now
                    flaggedCount += 1
                    logger.info("Flagged session \(session.id) for cleanup")
                }
            }

            // Also check archived sessions for auto-delete candidates
            let archivedDescriptor = FetchDescriptor<ChatSessionEntity>(
                predicate: #Predicate<ChatSessionEntity> { session in
                    session.isArchived && session.flaggedForCleanupAt == nil
                }
            )

            let archivedSessions = try modelContext.fetch(archivedDescriptor)

            for session in archivedSessions {
                if shouldFlagArchived(session: session, now: now) {
                    session.flaggedForCleanupAt = now
                    session.lifecycleRetention = RetentionPolicy.autoDeleteOK.rawValue
                    flaggedCount += 1
                    logger.info("Flagged archived session \(session.id) as auto-delete candidate")
                }
            }

            if flaggedCount > 0 {
                try modelContext.save()
                logger.info("Flagged \(flaggedCount) conversations for cleanup")
            }

        } catch {
            logger.error("Failed to flag stale conversations: \(error.localizedDescription)")
        }

        return flaggedCount
    }

    /// Determines if a non-archived session should be flagged.
    private func shouldFlag(session: ChatSessionEntity, now: Date) -> Bool {
        let lastActivity = session.lastActivityAt ?? session.updatedAt
        let daysSinceActivity =
            Calendar.current.dateComponents([.day], from: lastActivity, to: now).day ?? 0

        // Rule 1: >3 days inactive + intent == .quickQuestion → flag
        if daysSinceActivity > Self.quickQuestionStaleDays {
            let intent = session.afmIntent ?? session.lifecycleIntent
            if intent == ConversationIntent.quickQuestion.rawValue {
                return true
            }
        }

        // Rule 2: >7 days inactive + hasArtifacts == false → flag
        if daysSinceActivity > Self.noArtifactsStaleDays {
            if !session.hasArtifacts {
                return true
            }
        }

        return false
    }

    /// Determines if an archived session should be flagged for auto-delete.
    private func shouldFlagArchived(session: ChatSessionEntity, now: Date) -> Bool {
        let lastActivity = session.lastActivityAt ?? session.updatedAt
        let daysSinceActivity =
            Calendar.current.dateComponents([.day], from: lastActivity, to: now).day ?? 0

        // Rule 3: >14 days inactive + isArchived == true → auto-delete candidate
        return daysSinceActivity > Self.archivedAutoDeleteDays
    }

    // MARK: - Cleanup Actions

    /// Returns all sessions flagged for cleanup review.
    func flaggedSessions(modelContext: ModelContext) -> [ChatSessionEntity] {
        do {
            let descriptor = FetchDescriptor<ChatSessionEntity>(
                predicate: #Predicate<ChatSessionEntity> { session in
                    session.flaggedForCleanupAt != nil
                },
                sortBy: [SortDescriptor(\.flaggedForCleanupAt, order: .forward)]
            )
            return try modelContext.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch flagged sessions: \(error.localizedDescription)")
            return []
        }
    }

    /// Returns the count of sessions flagged for cleanup.
    func flaggedCount(modelContext: ModelContext) -> Int {
        do {
            let descriptor = FetchDescriptor<ChatSessionEntity>(
                predicate: #Predicate<ChatSessionEntity> { session in
                    session.flaggedForCleanupAt != nil
                }
            )
            return try modelContext.fetchCount(descriptor)
        } catch {
            logger.error("Failed to count flagged sessions: \(error.localizedDescription)")
            return 0
        }
    }

    /// Archives a session (moves to archived state).
    func archive(session: ChatSessionEntity, modelContext: ModelContext) {
        session.triggerDistillation(distillationService: distillationService, modelContext: modelContext)
        session.isArchived = true
        session.flaggedForCleanupAt = nil
        session.updatedAt = Date()

        do {
            try modelContext.save()
            logger.info("Archived session \(session.id)")
        } catch {
            logger.error("Failed to archive session: \(error.localizedDescription)")
        }
    }

    /// Archives multiple sessions.
    func archiveAll(_ sessions: [ChatSessionEntity], modelContext: ModelContext) {
        for session in sessions {
            session.triggerDistillation(distillationService: distillationService, modelContext: modelContext)
            session.isArchived = true
            session.flaggedForCleanupAt = nil
            session.updatedAt = Date()
        }

        do {
            try modelContext.save()
            logger.info("Archived \(sessions.count) sessions")
        } catch {
            logger.error("Failed to archive sessions: \(error.localizedDescription)")
        }
    }

    /// Unflags a session (keeps it, removes from cleanup queue).
    func keep(session: ChatSessionEntity, modelContext: ModelContext) {
        session.flaggedForCleanupAt = nil
        session.lifecycleRetention = RetentionPolicy.keep.rawValue
        session.updatedAt = Date()

        do {
            try modelContext.save()
            logger.info("Kept session \(session.id)")
        } catch {
            logger.error("Failed to keep session: \(error.localizedDescription)")
        }
    }

    /// Keeps all sessions (removes from cleanup queue).
    func keepAll(_ sessions: [ChatSessionEntity], modelContext: ModelContext) {
        for session in sessions {
            session.flaggedForCleanupAt = nil
            session.lifecycleRetention = RetentionPolicy.keep.rawValue
            session.updatedAt = Date()
        }

        do {
            try modelContext.save()
            logger.info("Kept \(sessions.count) sessions")
        } catch {
            logger.error("Failed to keep sessions: \(error.localizedDescription)")
        }
    }

    /// Deletes a session permanently.
    func delete(session: ChatSessionEntity, modelContext: ModelContext) {
        let sessionID = session.id
        session.triggerDistillation(distillationService: distillationService, modelContext: modelContext)
        modelContext.delete(session)

        do {
            try modelContext.save()
            logger.info("Deleted session \(sessionID)")
        } catch {
            logger.error("Failed to delete session: \(error.localizedDescription)")
        }
    }

    /// Deletes multiple sessions permanently.
    func deleteAll(_ sessions: [ChatSessionEntity], modelContext: ModelContext) {
        let count = sessions.count
        for session in sessions {
            session.triggerDistillation(distillationService: distillationService, modelContext: modelContext)
            modelContext.delete(session)
        }

        do {
            try modelContext.save()
            logger.info("Deleted \(count) sessions")
        } catch {
            logger.error("Failed to delete sessions: \(error.localizedDescription)")
        }
    }

    /// Unarchives a session (moves back to main view).
    func unarchive(session: ChatSessionEntity, modelContext: ModelContext) {
        session.isArchived = false
        session.updatedAt = Date()

        do {
            try modelContext.save()
            logger.info("Unarchived session \(session.id)")
        } catch {
            logger.error("Failed to unarchive session: \(error.localizedDescription)")
        }
    }
}
