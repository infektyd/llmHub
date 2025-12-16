//
//  MemoryRetrievalService.swift
//  llmHub
//
//  Created by Agent on 12/15/25.
//

import Foundation
import SwiftData
import os

private let logger = AppLogger.category("Memory")

/// Service for retrieving relevant memories for prompt injection.
final class MemoryRetrievalService: Sendable {

    struct MemorySnapshot: Sendable {
        let confidence: Double
        let scopeRaw: String
        let isComplete: Bool
        let summary: String
        let facts: [FallbackFact]
        let preferences: [FallbackPreference]
        let decisions: [FallbackDecision]
        let artifacts: [FallbackArtifact]
    }

    // MARK: - Configuration

    /// Maximum memories to return (token budget safety).
    private static let maxMemoriesToReturn = 3
    /// Require at least one keyword match.
    private static let minMatchCount: Int = 1

    // MARK: - Retrieval

    /// Retrieves relevant memories for a user message.
    /// - Parameters:
    ///   - userMessage: The user's input message.
    ///   - providerID: Optional provider ID to scope memories.
    ///   - modelContext: The SwiftData model context.
    /// - Returns: Array of relevant MemoryEntity, ranked by relevance.
    @MainActor
    func retrieveRelevant(
        for userMessage: String,
        providerID: String?,
        modelContext: ModelContext
    ) async -> [MemoryEntity] {
        // Keyword split (no stemming)
        let queryKeywords = extractQueryKeywords(from: userMessage)

        guard !queryKeywords.isEmpty else {
            logger.debug("No keywords extracted from user message, skipping memory retrieval")
            return []
        }

        logger.debug("Extracted query keywords: \(queryKeywords.joined(separator: ", "))")

        do {
            // Fetch all non-flagged memories
            let descriptor = FetchDescriptor<MemoryEntity>(
                predicate: #Predicate { !$0.isFlaggedForCleanup }
            )
            let allMemories = try modelContext.fetch(descriptor)

            // Score global memories first, then provider-scoped.
            let global = allMemories.filter { $0.providerID == nil }
            let providerScoped = allMemories.filter { $0.providerID != nil }

            let rankedGlobal = rank(
                memories: global, queryKeywords: queryKeywords, providerID: providerID)
            var topMemories = Array(rankedGlobal.prefix(Self.maxMemoriesToReturn))

            if topMemories.count < Self.maxMemoriesToReturn {
                let rankedProvider = rank(
                    memories: providerScoped, queryKeywords: queryKeywords, providerID: providerID)
                for mem in rankedProvider {
                    guard topMemories.count < Self.maxMemoriesToReturn else { break }
                    if !topMemories.contains(where: { $0.id == mem.id }) {
                        topMemories.append(mem)
                    }
                }
            }

            // Update access stats
            for memory in topMemories {
                memory.lastAccessedAt = Date()
                memory.accessCount += 1
                memory.logAccess()
            }

            if !topMemories.isEmpty {
                try modelContext.save()
            }

            logger.info("Retrieved \(topMemories.count) memories for query")

            #if DEBUG
                if !topMemories.isEmpty {
                    let ids = topMemories.map { $0.id.uuidString }.joined(separator: ",")
                    logger.debug("Memory retrieval hits: \(ids)")
                }
            #endif

            return Array(topMemories)

        } catch {
            logger.error("Failed to retrieve memories: \(error.localizedDescription)")
            return []
        }
    }

    @MainActor
    func retrieveRelevantXML(
        for userMessage: String,
        providerID: String?,
        modelContext: ModelContext
    ) async -> (count: Int, xml: String) {
        let snapshots = await retrieveRelevantSnapshots(
            for: userMessage,
            providerID: providerID,
            modelContext: modelContext
        )

        let xml = await Task {
            MemoryRetrievalService.formatSnapshotsForSystemPrompt(snapshots)
        }.value

        return (snapshots.count, xml)
    }

    @MainActor
    func retrieveRelevantSnapshots(
        for userMessage: String,
        providerID: String?,
        modelContext: ModelContext
    ) async -> [MemorySnapshot] {
        let memories = await retrieveRelevant(
            for: userMessage,
            providerID: providerID,
            modelContext: modelContext
        )

        return memories.map { memory in
            let facts: [FallbackFact] = {
                guard let data = memory.userFactsData else { return [] }
                return (try? JSONDecoder().decode([FallbackFact].self, from: data)) ?? []
            }()

            let preferences: [FallbackPreference] = {
                guard let data = memory.preferencesData else { return [] }
                return (try? JSONDecoder().decode([FallbackPreference].self, from: data)) ?? []
            }()

            let decisions: [FallbackDecision] = {
                guard let data = memory.decisionsData else { return [] }
                return (try? JSONDecoder().decode([FallbackDecision].self, from: data)) ?? []
            }()

            let artifacts: [FallbackArtifact] = {
                guard let data = memory.artifactsData else { return [] }
                return (try? JSONDecoder().decode([FallbackArtifact].self, from: data)) ?? []
            }()

            return MemorySnapshot(
                confidence: memory.confidence,
                scopeRaw: memory.scopeRaw,
                isComplete: memory.isComplete,
                summary: memory.summary,
                facts: facts,
                preferences: preferences,
                decisions: decisions,
                artifacts: artifacts
            )
        }
    }

    // MARK: - Formatting

    /// Formats memories as plain-text XML for system prompt injection.
    /// - Parameter memories: The memories to format.
    /// - Returns: XML string for system prompt.
    func formatForSystemPrompt(_ memories: [MemoryEntity]) -> String {
        guard !memories.isEmpty else { return "" }

        var xml = "<relevant_memories>\n"

        for memory in memories {
            let confidenceStr = String(format: "%.2f", memory.confidence)
            xml +=
                "  <memory confidence=\"\(confidenceStr)\" scope=\"\(memory.scopeRaw)\" isComplete=\"\(memory.isComplete ? "true" : "false")\">\n"
            xml += "    <summary>\(escapeXML(memory.summary))</summary>\n"

            // Add facts if present
            if let factsData = memory.userFactsData,
                let facts = try? JSONDecoder().decode([FallbackFact].self, from: factsData),
                !facts.isEmpty
            {
                xml += "    <user_facts>\n"
                for fact in facts {
                    xml +=
                        "      <fact category=\"\(escapeXML(fact.category))\">\(escapeXML(fact.statement))</fact>\n"
                }
                xml += "    </user_facts>\n"
            }

            // Add preferences if present
            if let prefsData = memory.preferencesData,
                let prefs = try? JSONDecoder().decode([FallbackPreference].self, from: prefsData),
                !prefs.isEmpty
            {
                xml += "    <preferences>\n"
                for pref in prefs {
                    xml +=
                        "      <preference topic=\"\(escapeXML(pref.topic))\">\(escapeXML(pref.value))</preference>\n"
                }
                xml += "    </preferences>\n"
            }

            // Add decisions if present
            if let decisionsData = memory.decisionsData,
                let decisions = try? JSONDecoder().decode(
                    [FallbackDecision].self, from: decisionsData),
                !decisions.isEmpty
            {
                xml += "    <decisions>\n"
                for decision in decisions {
                    xml += "      <decision>\(escapeXML(decision.decision))</decision>\n"
                }
                xml += "    </decisions>\n"
            }

            // Add artifacts if present
            if let artifactsData = memory.artifactsData,
                let artifacts = try? JSONDecoder().decode(
                    [FallbackArtifact].self, from: artifactsData),
                !artifacts.isEmpty
            {
                xml += "    <artifacts>\n"
                for artifact in artifacts {
                    let type = escapeXML(artifact.type)
                    let desc = escapeXML(artifact.description)
                    let langAttr = artifact.language.map { " language=\"\(escapeXML($0))\"" } ?? ""
                    xml += "      <artifact type=\"\(type)\"\(langAttr)>\(desc)</artifact>\n"
                }
                xml += "    </artifacts>\n"
            }

            xml += "  </memory>\n"
        }

        xml += "</relevant_memories>"

        logger.debug("Formatted \(memories.count) memories as XML (\(xml.count) chars)")
        return xml
    }

    /// Formats memory snapshots (Sendable) as XML off-main.
    /// - Parameter snapshots: Array of MemorySnapshot structs.
    /// - Returns: XML string for system prompt.
    static func formatSnapshotsForSystemPrompt(_ snapshots: [MemorySnapshot]) -> String {
        guard !snapshots.isEmpty else { return "" }

        var xml = "<relevant_memories>\n"

        for snapshot in snapshots {
            let confidenceStr = String(format: "%.2f", snapshot.confidence)
            xml +=
                "  <memory confidence=\"\(confidenceStr)\" scope=\"\(snapshot.scopeRaw)\" isComplete=\"\(snapshot.isComplete ? "true" : "false")\">\n"
            xml += "    <summary>\(escapeXMLStatic(snapshot.summary))</summary>\n"

            // Add facts if present
            if !snapshot.facts.isEmpty {
                xml += "    <user_facts>\n"
                for fact in snapshot.facts {
                    xml +=
                        "      <fact category=\"\(escapeXMLStatic(fact.category))\">\(escapeXMLStatic(fact.statement))</fact>\n"
                }
                xml += "    </user_facts>\n"
            }

            // Add preferences if present
            if !snapshot.preferences.isEmpty {
                xml += "    <preferences>\n"
                for pref in snapshot.preferences {
                    xml +=
                        "      <preference topic=\"\(escapeXMLStatic(pref.topic))\">\(escapeXMLStatic(pref.value))</preference>\n"
                }
                xml += "    </preferences>\n"
            }

            // Add decisions if present
            if !snapshot.decisions.isEmpty {
                xml += "    <decisions>\n"
                for decision in snapshot.decisions {
                    xml += "      <decision>\(escapeXMLStatic(decision.decision))</decision>\n"
                }
                xml += "    </decisions>\n"
            }

            // Add artifacts if present
            if !snapshot.artifacts.isEmpty {
                xml += "    <artifacts>\n"
                for artifact in snapshot.artifacts {
                    let type = escapeXMLStatic(artifact.type)
                    let desc = escapeXMLStatic(artifact.description)
                    let langAttr =
                        artifact.language.map { " language=\"\(escapeXMLStatic($0))\"" } ?? ""
                    xml += "      <artifact type=\"\(type)\"\(langAttr)>\(desc)</artifact>\n"
                }
                xml += "    </artifacts>\n"
            }

            xml += "  </memory>\n"
        }

        xml += "</relevant_memories>"
        return xml
    }

    // MARK: - Ranking

    private func rank(
        memories: [MemoryEntity],
        queryKeywords: [String],
        providerID: String?
    ) -> [MemoryEntity] {
        var scored: [(MemoryEntity, Double)] = []

        for memory in memories {
            // Provider filter (nil means global)
            if let memProvider = memory.providerID {
                guard let queryProvider = providerID else { continue }
                guard memProvider.lowercased() == queryProvider.lowercased() else { continue }
            }

            let matchCount = keywordMatchCount(memory: memory, queryKeywords: queryKeywords)
            guard matchCount >= Self.minMatchCount else { continue }

            let score = calculateRelevanceScore(
                memory: memory,
                matchCount: matchCount,
                queryKeywordCount: queryKeywords.count
            )

            scored.append((memory, score))
        }

        scored.sort { lhs, rhs in
            if abs(lhs.1 - rhs.1) < 0.01 {
                return lhs.0.createdAt > rhs.0.createdAt
            }
            return lhs.1 > rhs.1
        }

        return scored.map { $0.0 }
    }

    private func keywordMatchCount(memory: MemoryEntity, queryKeywords: [String]) -> Int {
        let haystack =
            (memory.concatenatedKeywords.isEmpty ? memory.keywords : memory.concatenatedKeywords)
        guard !haystack.isEmpty else { return 0 }
        return queryKeywords.reduce(0) { count, kw in
            count + (haystack.localizedStandardContains(kw) ? 1 : 0)
        }
    }

    private func calculateRelevanceScore(
        memory: MemoryEntity,
        matchCount: Int,
        queryKeywordCount: Int
    ) -> Double {
        // Match count score (40%)
        let matchScore = Double(matchCount) / Double(max(queryKeywordCount, 1))

        // Recency score (30%) - decays over 30 days based on creation date
        let daysSinceCreated =
            Calendar.current.dateComponents(
                [.day],
                from: memory.createdAt,
                to: Date()
            ).day ?? 0
        let recencyScore = max(0, 1.0 - Double(daysSinceCreated) / 30.0)

        // Confidence score (30%), downgraded when distillation incomplete
        let effectiveConfidence = memory.isComplete ? memory.confidence : (memory.confidence * 0.5)

        return (recencyScore * 0.3) + (matchScore * 0.4) + (effectiveConfidence * 0.3)
    }

    private func extractQueryKeywords(from text: String) -> [String] {
        let words =
            text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }

        // Stable de-dupe
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(words.count)
        for w in words {
            if seen.insert(w).inserted {
                result.append(w)
            }
        }
        return result
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func escapeXMLStatic(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
