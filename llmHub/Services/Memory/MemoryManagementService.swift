//
//  MemoryManagementService.swift
//  llmHub
//
//  Created by Agent on 12/15/25.
//

import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.llmhub", category: "MemoryManagement")

/// Service for CRUD operations and lifecycle management of memories.
@MainActor
final class MemoryManagementService {

    // MARK: - Configuration

    /// Days without access before flagging for cleanup.
    private static let unusedDaysThreshold = 30
    /// Minimum access count to avoid cleanup flagging.
    private static let minAccessCountForRetention = 2

    // MARK: - CRUD Operations

    /// Creates a new memory.
    /// - Parameters:
    ///   - memory: The memory domain model to persist.
    ///   - modelContext: The SwiftData model context.
    func create(_ memory: Memory, modelContext: ModelContext) throws {
        let entity = MemoryEntity(memory: memory)
        modelContext.insert(entity)
        try modelContext.save()
        entity.logCreation()
        logger.info("Created memory: \(entity.id)")
    }

    /// Updates an existing memory.
    /// - Parameters:
    ///   - memory: The updated memory domain model.
    ///   - modelContext: The SwiftData model context.
    func update(_ memory: Memory, modelContext: ModelContext) throws {
        let memoryID = memory.id
        guard
            let entity = try modelContext.fetch(
                FetchDescriptor<MemoryEntity>(predicate: #Predicate { $0.id == memoryID })
            ).first
        else {
            throw MemoryManagementError.memoryNotFound
        }

        // Update fields
        entity.scopeRaw = (memory.providerID == nil ? MemoryScope.global.rawValue : MemoryScope.provider.rawValue)
        entity.scopeIdentifier = memory.providerID
        entity.providerID = memory.providerID
        entity.summary = memory.summary
        entity.userFactsData = try? JSONEncoder().encode(memory.userFacts)
        entity.preferencesData = try? JSONEncoder().encode(memory.preferences)
        entity.decisionsData = try? JSONEncoder().encode(memory.decisions)
        entity.artifactsData = try? JSONEncoder().encode(memory.artifacts)
        let cappedKeywords = Array(memory.keywords.prefix(20))
        entity.keywords = cappedKeywords.joined(separator: " ")
        entity.concatenatedKeywords = cappedKeywords.joined(separator: " ")
        entity.confidence = memory.confidence
        entity.isComplete = memory.isComplete

        try modelContext.save()
        logger.info("Updated memory: \(entity.id)")
    }

    /// Deletes a memory by ID.
    /// - Parameters:
    ///   - id: The memory ID to delete.
    ///   - modelContext: The SwiftData model context.
    func delete(id: UUID, modelContext: ModelContext) throws {
        guard
            let entity = try modelContext.fetch(
                FetchDescriptor<MemoryEntity>(predicate: #Predicate { $0.id == id })
            ).first
        else {
            throw MemoryManagementError.memoryNotFound
        }

        modelContext.delete(entity)
        try modelContext.save()
        logger.info("Deleted memory: \(id)")
    }

    /// Fetches a memory by ID.
    /// - Parameters:
    ///   - id: The memory ID.
    ///   - modelContext: The SwiftData model context.
    /// - Returns: The memory domain model, or nil if not found.
    func fetch(id: UUID, modelContext: ModelContext) throws -> Memory? {
        let entity = try modelContext.fetch(
            FetchDescriptor<MemoryEntity>(predicate: #Predicate { $0.id == id })
        ).first
        return entity?.asDomain()
    }

    /// Fetches all memories.
    /// - Parameter modelContext: The SwiftData model context.
    /// - Returns: Array of all memory domain models.
    func fetchAll(modelContext: ModelContext) throws -> [Memory] {
        let entities = try modelContext.fetch(
            FetchDescriptor<MemoryEntity>(
                sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)]
            )
        )
        return entities.map { $0.asDomain() }
    }

    // MARK: - Access Tracking

    /// Records an access to a memory, updating stats.
    /// - Parameters:
    ///   - id: The memory ID.
    ///   - modelContext: The SwiftData model context.
    func recordAccess(id: UUID, modelContext: ModelContext) throws {
        guard
            let entity = try modelContext.fetch(
                FetchDescriptor<MemoryEntity>(predicate: #Predicate { $0.id == id })
            ).first
        else {
            throw MemoryManagementError.memoryNotFound
        }

        entity.lastAccessedAt = Date()
        entity.accessCount += 1
        entity.isFlaggedForCleanup = false  // Unflag if accessed

        try modelContext.save()
        entity.logAccess()
    }

    // MARK: - Lifecycle / Decay

    /// Flags unused memories for cleanup based on access patterns.
    /// - Parameter modelContext: The SwiftData model context.
    /// - Returns: Number of memories flagged.
    func flagUnused(modelContext: ModelContext) async -> Int {
        let now = Date()
        var flaggedCount = 0

        do {
            // Fetch memories that haven't been accessed recently
            let descriptor = FetchDescriptor<MemoryEntity>(
                predicate: #Predicate { !$0.isFlaggedForCleanup }
            )
            let memories = try modelContext.fetch(descriptor)

            for memory in memories {
                let daysSinceAccess =
                    Calendar.current.dateComponents(
                        [.day],
                        from: memory.lastAccessedAt,
                        to: now
                    ).day ?? 0

                // Flag if: old + rarely accessed
                if daysSinceAccess > Self.unusedDaysThreshold
                    && memory.accessCount < Self.minAccessCountForRetention
                {
                    memory.isFlaggedForCleanup = true
                    flaggedCount += 1
                    logger.debug(
                        "Flagged memory \(memory.id) for cleanup (days=\(daysSinceAccess), accesses=\(memory.accessCount))"
                    )
                }
            }

            if flaggedCount > 0 {
                try modelContext.save()
                logger.info("Flagged \(flaggedCount) memories for cleanup")
            }

        } catch {
            logger.error("Failed to flag unused memories: \(error.localizedDescription)")
        }

        return flaggedCount
    }

    /// Deletes all memories flagged for cleanup.
    /// - Parameter modelContext: The SwiftData model context.
    /// - Returns: Number of memories deleted.
    func cleanupFlagged(modelContext: ModelContext) async -> Int {
        var deletedCount = 0

        do {
            let descriptor = FetchDescriptor<MemoryEntity>(
                predicate: #Predicate { $0.isFlaggedForCleanup }
            )
            let flaggedMemories = try modelContext.fetch(descriptor)

            for memory in flaggedMemories {
                modelContext.delete(memory)
                deletedCount += 1
            }

            if deletedCount > 0 {
                try modelContext.save()
                logger.info("Cleaned up \(deletedCount) flagged memories")
            }

        } catch {
            logger.error("Failed to cleanup flagged memories: \(error.localizedDescription)")
        }

        return deletedCount
    }

    /// Returns statistics about memory usage.
    /// - Parameter modelContext: The SwiftData model context.
    /// - Returns: Memory statistics.
    func statistics(modelContext: ModelContext) throws -> MemoryStatistics {
        let allMemories = try modelContext.fetch(FetchDescriptor<MemoryEntity>())

        let globalCount = allMemories.filter { $0.scope == .global }.count
        let providerCount = allMemories.filter { $0.scope == .provider }.count
        let flaggedCount = allMemories.filter { $0.isFlaggedForCleanup }.count
        let totalAccesses = allMemories.reduce(0) { $0 + $1.accessCount }

        return MemoryStatistics(
            totalCount: allMemories.count,
            globalCount: globalCount,
            providerCount: providerCount,
            flaggedForCleanup: flaggedCount,
            totalAccesses: totalAccesses
        )
    }
}

// MARK: - Supporting Types

/// Statistics about memory usage.
struct MemoryStatistics: Sendable {
    let totalCount: Int
    let globalCount: Int
    let providerCount: Int
    let flaggedForCleanup: Int
    let totalAccesses: Int
}

/// Errors thrown by MemoryManagementService.
enum MemoryManagementError: LocalizedError {
    case memoryNotFound

    var errorDescription: String? {
        switch self {
        case .memoryNotFound:
            return "Memory not found"
        }
    }
}
