//
//  MemoryModels.swift
//  llmHub
//
//  Created by Agent on 12/15/25.
//

import Foundation
import FoundationModels
import SwiftData
import os

// MARK: - Memory Scope

/// Defines the scope/visibility of a memory.
enum MemoryScope: String, Codable, CaseIterable, Sendable {
    /// Global memories apply across all sessions and providers.
    case global = "global"
    /// Provider-specific memories apply only to sessions using that provider.
    case provider = "provider"
}

// MARK: - Extracted Types (For AFM @Generable)

/// A fact about the user extracted from conversation.
@available(macOS 15.0, iOS 18.0, *)
@Generable
struct ExtractedFact: Sendable, Codable {
    /// The factual statement about the user (e.g., "User prefers Swift over Objective-C").
    var statement: String
    /// Category: "technical", "personal", "workflow", "preference".
    var category: String
}

/// A user preference extracted from conversation.
@available(macOS 15.0, iOS 18.0, *)
@Generable
struct ExtractedPreference: Sendable, Codable {
    /// What the preference is about (e.g., "code style").
    var topic: String
    /// The preferred value or approach.
    var value: String
}

/// A decision made during the conversation.
@available(macOS 15.0, iOS 18.0, *)
@Generable
struct ExtractedDecision: Sendable, Codable {
    /// Description of the decision.
    var decision: String
    /// Context or rationale.
    var context: String
}

/// An artifact produced during the conversation.
@available(macOS 15.0, iOS 18.0, *)
@Generable
struct ExtractedArtifact: Sendable, Codable {
    /// Type of artifact: "code", "config", "document", "command".
    var type: String
    /// Brief description.
    var description: String
    /// Language or format if applicable.
    var language: String?
}

/// The distilled essence of a conversation, extracted by AFM.
@available(macOS 15.0, iOS 18.0, *)
@Generable
struct ConversationEssence: Sendable, Codable {
    /// A concise 1-2 sentence summary of the conversation.
    var summary: String
    /// Facts about the user discovered in this conversation (max 5).
    var userFacts: [ExtractedFact]
    /// User preferences expressed or inferred (max 5).
    var preferences: [ExtractedPreference]
    /// Decisions made during the conversation (max 3).
    var decisions: [ExtractedDecision]
    /// Notable artifacts produced (max 3).
    var artifacts: [ExtractedArtifact]
    /// Keywords for search/retrieval (STRICT MAX 20). Optimize for high-signal search terms.
    var keywords: [String]
}

// MARK: - Non-Generable Fallback Types

/// Non-@Generable versions for fallback and persistence.
struct FallbackFact: Codable, Sendable, Equatable {
    var statement: String
    var category: String
}

struct FallbackPreference: Codable, Sendable, Equatable {
    var topic: String
    var value: String
}

struct FallbackDecision: Codable, Sendable, Equatable {
    var decision: String
    var context: String
}

struct FallbackArtifact: Codable, Sendable, Equatable {
    var type: String
    var description: String
    var language: String?
}

/// Fallback essence for when AFM is unavailable.
struct FallbackEssence: Codable, Sendable {
    var summary: String
    var userFacts: [FallbackFact]
    var preferences: [FallbackPreference]
    var decisions: [FallbackDecision]
    var artifacts: [FallbackArtifact]
    var keywords: [String]

    static func empty() -> FallbackEssence {
        FallbackEssence(
            summary: "",
            userFacts: [],
            preferences: [],
            decisions: [],
            artifacts: [],
            keywords: []
        )
    }
}

// MARK: - Domain Model

/// Domain model for a memory, used in business logic.
struct Memory: Identifiable, Sendable {
    let id: UUID
    /// Provider scope. Nil means global.
    var providerID: String?
    var summary: String
    var userFacts: [FallbackFact]
    var preferences: [FallbackPreference]
    var decisions: [FallbackDecision]
    var artifacts: [FallbackArtifact]
    var keywords: [String]
    /// True when distillation completed successfully; false when saved from an error/cancel.
    var isComplete: Bool
    var confidence: Double
    var sourceSessionID: UUID?
    var createdAt: Date
    var lastAccessedAt: Date
    var accessCount: Int

    nonisolated init(
        id: UUID = UUID(),
        providerID: String? = nil,
        summary: String,
        userFacts: [FallbackFact] = [],
        preferences: [FallbackPreference] = [],
        decisions: [FallbackDecision] = [],
        artifacts: [FallbackArtifact] = [],
        keywords: [String] = [],
        isComplete: Bool = true,
        confidence: Double = 1.0,
        sourceSessionID: UUID? = nil,
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date(),
        accessCount: Int = 0
    ) {
        self.id = id
        self.providerID = providerID
        self.summary = summary
        self.userFacts = userFacts
        self.preferences = preferences
        self.decisions = decisions
        self.artifacts = artifacts
        self.keywords = Array(keywords.prefix(20))
        self.isComplete = isComplete
        self.confidence = confidence
        self.sourceSessionID = sourceSessionID
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.accessCount = accessCount
    }
}

// MARK: - SwiftData Entity

/// Persisted memory entity in SwiftData.
@Model
final class MemoryEntity {
    /// Unique identifier.
    @Attribute(.unique) var id: UUID
    /// Scope: "global" or "provider".
    var scopeRaw: String
    /// For provider scope, the provider ID (legacy mirror).
    var scopeIdentifier: String?
    /// Provider ID for provider-scoped memories. Nil means global.
    var providerID: String?
    /// Concise summary of the memory.
    var summary: String
    /// JSON-encoded [FallbackFact].
    var userFactsData: Data?
    /// JSON-encoded [FallbackPreference].
    var preferencesData: Data?
    /// JSON-encoded [FallbackDecision].
    var decisionsData: Data?
    /// JSON-encoded [FallbackArtifact].
    var artifactsData: Data?
    /// Space-separated keywords for text search (legacy).
    var keywords: String
    /// Space-separated keywords for retrieval (Phase 2).
    var concatenatedKeywords: String = ""
    /// Confidence score 0.0-1.0.
    var confidence: Double
    /// Whether this memory was fully distilled. False when saved from an error/cancel.
    var isComplete: Bool = true
    /// Source conversation session ID.
    var sourceSessionID: UUID?
    /// When this memory was created.
    var createdAt: Date
    /// When this memory was last accessed for retrieval.
    var lastAccessedAt: Date
    /// How many times this memory has been retrieved.
    var accessCount: Int
    /// Whether this memory has been flagged for cleanup.
    var isFlaggedForCleanup: Bool

    /// Computed scope from raw string.
    var scope: MemoryScope {
        get { MemoryScope(rawValue: scopeRaw) ?? .global }
        set { scopeRaw = newValue.rawValue }
    }

    // Logger specifically for MemoryEntity to avoid top-level isolation issues
    private static let logger = Logger(subsystem: "com.llmhub", category: "Memory")

    init(memory: Memory) {
        self.id = memory.id
        self.scopeRaw =
            (memory.providerID == nil ? MemoryScope.global.rawValue : MemoryScope.provider.rawValue)
        self.scopeIdentifier = memory.providerID
        self.providerID = memory.providerID
        self.summary = memory.summary
        self.userFactsData = try? JSONEncoder().encode(memory.userFacts)
        self.preferencesData = try? JSONEncoder().encode(memory.preferences)
        self.decisionsData = try? JSONEncoder().encode(memory.decisions)
        self.artifactsData = try? JSONEncoder().encode(memory.artifacts)
        let cappedKeywords = Array(memory.keywords.prefix(20))
        self.keywords = cappedKeywords.joined(separator: " ")
        self.concatenatedKeywords = cappedKeywords.joined(separator: " ")
        self.confidence = memory.confidence
        self.isComplete = memory.isComplete
        self.sourceSessionID = memory.sourceSessionID
        self.createdAt = memory.createdAt
        self.lastAccessedAt = memory.lastAccessedAt
        self.accessCount = memory.accessCount
        self.isFlaggedForCleanup = false
    }

    /// Converts entity to domain model.
    func asDomain() -> Memory {
        let facts =
            (try? JSONDecoder().decode([FallbackFact].self, from: userFactsData ?? Data())) ?? []
        let prefs =
            (try? JSONDecoder().decode([FallbackPreference].self, from: preferencesData ?? Data()))
            ?? []
        let decs =
            (try? JSONDecoder().decode([FallbackDecision].self, from: decisionsData ?? Data()))
            ?? []
        let arts =
            (try? JSONDecoder().decode([FallbackArtifact].self, from: artifactsData ?? Data()))
            ?? []
        let keywordsSource = concatenatedKeywords.isEmpty ? keywords : concatenatedKeywords
        let kws = keywordsSource.split(separator: " ").map(String.init)

        return Memory(
            id: id,
            providerID: providerID,
            summary: summary,
            userFacts: facts,
            preferences: prefs,
            decisions: decs,
            artifacts: arts,
            keywords: kws,
            isComplete: isComplete,
            confidence: confidence,
            sourceSessionID: sourceSessionID,
            createdAt: createdAt,
            lastAccessedAt: lastAccessedAt,
            accessCount: accessCount
        )
    }

    /// Debug log for memory creation.
    func logCreation() {
        #if DEBUG
            Self.logger.debug(
                "Memory created: id=\(self.id), scope=\(self.scopeRaw), keywords='\(self.keywords.prefix(100))'"
            )
        #endif
    }

    /// Debug log for memory access.
    func logAccess() {
        #if DEBUG
            Self.logger.debug(
                "Memory accessed: id=\(self.id), accessCount=\(self.accessCount)"
            )
        #endif
    }
}
