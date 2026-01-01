//
//  ConversationDistillationService.swift
//  llmHub
//
//  Created by Agent on 12/15/25.
//

import Foundation
import FoundationModels
import SwiftData
import os

private let logger = AppLogger.category("Memory")

/// Service for distilling conversations into persistent memories using Apple Foundation Models.
/// Runs in background, non-blocking, with graceful fallback when AFM is unavailable.
@MainActor
final class ConversationDistillationService {

    // MARK: - Configuration

    /// Maximum messages to consider for distillation (token budget safety).
    private static let maxMessagesForDistillation = 15
    /// Minimum messages required to warrant distillation.
    private static let minMessagesForDistillation = 3
    /// Maximum token budget for AFM input context.
    private static let maxContextTokens = 4096

    // Constant for prompt overhead estimation (heuristic)
    private static let promptTemplateOverheadTokens = 250

    // MARK: - Availability

    enum AFMSupportStatus: Sendable, Equatable {
        case unsupportedOS
        case unsupportedHardware
        case unavailable(reason: String)
        case available
    }

    private enum AFMUserDefaultsKeys {
        static let unavailableCount = "afm.unavailable.count"
        static let unavailableLastAt = "afm.unavailable.lastAt"
        static let unavailableLastReason = "afm.unavailable.lastReason"
        static let shouldShowUserHint = "afm.unavailable.shouldShowHint"
    }

    /// Check if AFM is available on this device.
    var isAvailable: Bool {
        switch afmSupportStatus() {
        case .available:
            return true
        case .unsupportedOS, .unsupportedHardware, .unavailable:
            return false
        }
    }

    func afmSupportStatus() -> AFMSupportStatus {
        if #available(macOS 15.0, iOS 18.0, *) {
            // Check SystemLanguageModel availability status
            if SystemLanguageModel.default.availability == .available {
                return .available
            }
            return .unavailable(
                reason: "Apple Intelligence is disabled or model assets are not downloaded yet."
            )
        }

        return .unsupportedOS
    }

    // MARK: - Distillation

    /// Distills a conversation session into a memory entity.
    /// This method is non-blocking and runs in a background task.
    /// - Parameters:
    ///   - session: The chat session to distill.
    ///   - modelContext: The SwiftData model context.
    func distill(session: ChatSessionEntity, modelContext: ModelContext) async {
        let snapshotMessages = session.messages.map { $0.asDomain() }
        await distill(
            sessionID: session.id,
            providerID: session.providerID,
            messages: snapshotMessages,
            modelContext: modelContext
        )
    }

    /// Distills a conversation snapshot into a memory entity.
    /// Use this when the session may be deleted soon (e.g., delete flows).
    func distill(
        sessionID: UUID,
        providerID: String,
        messages: [ChatMessage],
        modelContext: ModelContext
    ) async {
        // Guard: Skip if too few messages
        guard messages.count >= Self.minMessagesForDistillation else {
            logger.debug(
                "Skipping distillation for session \(sessionID): too few messages (\(messages.count))"
            )
            return
        }

        // Guard: Silent skip if AFM unavailable, but record persistent issues for UI hinting.
        if !isAvailable {
            let status = afmSupportStatus()
            switch status {
            case .unavailable(let reason):
                logger.debug(
                    "Skipping distillation for session \(sessionID): AFM unavailable: \(reason)"
                )
                recordAFMUnavailability(reason: reason)
            case .unsupportedHardware:
                logger.debug("Skipping distillation for session \(sessionID): unsupported hardware")
            case .unsupportedOS:
                logger.debug("Skipping distillation for session \(sessionID): unsupported OS")
            case .available:
                break  // Should be covered by isAvailable check
            }
            return
        }

        // Check if already has a memory
        let existingMemory = try? modelContext.fetch(
            FetchDescriptor<MemoryEntity>(
                predicate: #Predicate { $0.sourceSessionID == sessionID }
            )
        ).first

        if existingMemory != nil {
            logger.debug("Skipping distillation for session \(sessionID): memory already exists")
            return
        }

        // Snapshot messages for distillation (sorted, last N, token-aware truncate)
        let sorted = messages.sorted { $0.createdAt < $1.createdAt }
        let truncated = truncateForDistillation(messages: sorted)

        logger.debug(
            "Distillation input for session \(sessionID): \(truncated.count) messages, ~\(TokenEstimator.estimate(messages: truncated)) tokens"
        )

        do {
            if #available(macOS 15.0, iOS 18.0, *) {
                let memory = try await distillWithAFM(
                    messages: truncated,
                    providerID: providerID,
                    sessionID: sessionID
                )
                try persist(memory: memory, modelContext: modelContext)
                logger.info("Distilled session \(sessionID) into memory")
            } else {
                // This path should be unreachable due to early guards, but safe fallback logic exists.
                logger.debug("Skipping distillation for session \(sessionID): unsupported OS")
            }
        } catch {
            // Attempt partial save on error/interrupt.
            logger.error(
                "Distillation failed for session \(sessionID): \(error.localizedDescription)")

            if isAFMAssetsUnavailable(error) {
                recordAFMUnavailability(reason: "Model assets are unavailable")
            }

            let partial = partialMemory(
                from: truncated, providerID: providerID, sessionID: sessionID)
            do {
                try persist(memory: partial, modelContext: modelContext)
                logger.debug("Saved partial memory for session \(sessionID)")
            } catch {
                logger.error(
                    "Failed to save partial memory for session \(sessionID): \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - AFM Distillation

    @available(macOS 15.0, iOS 18.0, *)
    private func distillWithAFM(
        messages: [ChatMessage],
        providerID: String,
        sessionID: UUID
    ) async throws -> Memory {
        // Build context from messages
        let context = buildDistillationContext(from: messages)
        let prompt = makeDistillationPrompt(conversationContext: context)

        FoundationModelsDiagnostics.logRequestStart(useCase: "conversation_distillation")
        let start = CFAbsoluteTimeGetCurrent()

        do {
            // Phase 2: use SystemLanguageModel content tagging adapter.
            let model = SystemLanguageModel(useCase: .contentTagging)
            let session = LanguageModelSession(model: model)
            let response = try await session.respond(
                to: prompt,
                generating: ConversationEssence.self
            )
            let essence = response.content

            let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000
            FoundationModelsDiagnostics.logRequestSuccess(latencyMs: latency)

            return Memory(
                providerID: providerID,
                summary: essence.summary,
                userFacts: Array(essence.userFacts.prefix(5)).map {
                    FallbackFact(statement: $0.statement, category: $0.category)
                },
                preferences: Array(essence.preferences.prefix(5)).map {
                    FallbackPreference(topic: $0.topic, value: $0.value)
                },
                decisions: Array(essence.decisions.prefix(3)).map {
                    FallbackDecision(decision: $0.decision, context: $0.context)
                },
                artifacts: Array(essence.artifacts.prefix(3)).map {
                    FallbackArtifact(
                        type: $0.type, description: $0.description, language: $0.language)
                },
                keywords: Array(essence.keywords.prefix(20)),
                isComplete: true,
                confidence: 0.9,
                sourceSessionID: sessionID
            )
        } catch {
            let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000
            FoundationModelsDiagnostics.logRequestFail(latencyMs: latency, error: error)
            throw error
        }
    }

    // MARK: - Helpers

    private func buildDistillationContext(from messages: [ChatMessage]) -> String {
        messages.map { msg in
            let role = msg.role.rawValue.capitalized
            let content = String(msg.content.prefix(1200))
            return "\(role): \(content)"
        }.joined(separator: "\n\n")
    }

    @available(macOS 15.0, iOS 18.0, *)
    private func makeDistillationPrompt(conversationContext: String) -> String {
        """
        You are distilling a chat transcript into durable memory for later retrieval.

        Return a structured object matching the requested schema.

        CONVERSATION (most recent):
        \(conversationContext)

        EXTRACTION RULES:
        - summary: 1–2 sentences, concrete, no filler.
        - userFacts: up to 5 facts about the user (statement + category).
        - preferences: up to 5 stable preferences (topic + value).
        - decisions: up to 3 explicit decisions made.
        - artifacts: up to 3 notable outputs (code/config/commands/docs) with optional language.
        - keywords: EXACTLY 5–20 high-value terms for search retrieval.

        KEYWORDS GUIDANCE:
        - STRICT LIMIT: Do NOT exceed 20 keywords. The system will truncate > 20.
        - CONTENT: Prefer specific nouns, proper names, API names, tool names.
        - EXCLUDE: Stop words (the, a, is), generic terms (help, code, assistant), verbs.
        - FORMAT: Single words or short phrases.
        """
    }

    private func truncateForDistillation(messages: [ChatMessage]) -> [ChatMessage] {
        guard !messages.isEmpty else { return [] }

        var candidate = Array(messages.suffix(Self.maxMessagesForDistillation))

        while candidate.count > Self.minMessagesForDistillation {
            let context = buildDistillationContext(from: candidate)
            // Account for the prompt template itself roughly + context
            let estimatedTotal: Int

            // Simple heuristic check first to avoid expensive tokenization if obvious
            if context.count < 1000 {
                // ~250 tokens for 1000 chars, well within limit
                break
            }

            if #available(macOS 15.0, iOS 18.0, *) {
                // If we can, measure the actual full prompt
                // But avoid building the full string repeatedly if possible
                let promptPreview = makeDistillationPrompt(conversationContext: context)
                estimatedTotal = TokenEstimator.estimate(promptPreview)
            } else {
                // Fallback estimation
                estimatedTotal =
                    TokenEstimator.estimate(context) + Self.promptTemplateOverheadTokens
            }

            if estimatedTotal <= Self.maxContextTokens {
                break
            }
            candidate.removeFirst()
        }

        return candidate
    }

    private func partialMemory(from messages: [ChatMessage], providerID: String, sessionID: UUID)
        -> Memory
    {
        let allContent = messages.map { $0.content }.joined(separator: " ")
        let keywords = extractKeywords(from: allContent, maxCount: 20)

        let firstUserContent = messages.first { $0.role == .user }?.content ?? ""
        let summary = String(firstUserContent.prefix(200))

        var artifacts: [FallbackArtifact] = []
        for message in messages where !message.codeBlocks.isEmpty {
            for block in message.codeBlocks.prefix(3) {
                artifacts.append(
                    FallbackArtifact(
                        type: "code",
                        description: "Code snippet",
                        language: block.language
                    ))
            }
        }

        return Memory(
            providerID: providerID,
            summary: summary,
            userFacts: [],
            preferences: [],
            decisions: [],
            artifacts: artifacts,
            keywords: keywords,
            isComplete: false,
            confidence: 0.5,
            sourceSessionID: sessionID
        )
    }

    private func persist(memory: Memory, modelContext: ModelContext) throws {
        let entity = MemoryEntity(memory: memory)
        modelContext.insert(entity)
        try modelContext.save()
        entity.logCreation()
    }

    private func isAFMAssetsUnavailable(_ error: Error) -> Bool {
        let description = error.localizedDescription.lowercased()
        let debug = String(describing: error).lowercased()

        // Common error strings for missing assets in Foundation Models
        let assetIndicators = [
            "model assets",
            "assets are unavailable",
            "resource unavailable",
            "assets missing",
            "download required",
        ]

        for indicator in assetIndicators {
            if description.contains(indicator) || debug.contains(indicator) {
                return true
            }
        }

        return false
    }

    private func recordAFMUnavailability(reason: String) {
        let defaults = UserDefaults.standard
        let now = Date()

        let lastAt = defaults.object(forKey: AFMUserDefaultsKeys.unavailableLastAt) as? Date
        let lastReason = defaults.string(forKey: AFMUserDefaultsKeys.unavailableLastReason)
        let previousCount = defaults.integer(forKey: AFMUserDefaultsKeys.unavailableCount)

        let isSameReason = (lastReason == reason)
        // Reset count if it's been more than 24 hours
        let isRecent = (lastAt.map { now.timeIntervalSince($0) < 24 * 60 * 60 } ?? false)

        let newCount: Int
        if isSameReason && isRecent {
            newCount = previousCount + 1
        } else {
            newCount = 1
        }

        defaults.set(now, forKey: AFMUserDefaultsKeys.unavailableLastAt)
        defaults.set(reason, forKey: AFMUserDefaultsKeys.unavailableLastReason)
        defaults.set(newCount, forKey: AFMUserDefaultsKeys.unavailableCount)

        // Show hint on 2nd failure in 24h
        if newCount >= 2 {
            defaults.set(true, forKey: AFMUserDefaultsKeys.shouldShowUserHint)
            NotificationCenter.default.post(
                name: .afmUserHintNeeded,
                object: nil,
                userInfo: ["reason": reason]
            )
        }
    }

    private func extractKeywords(from text: String, maxCount: Int) -> [String] {
        // Simple stop-word filtering and word extraction
        let stopWords: Set<String> = [
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
            "of", "with", "by", "from", "as", "is", "was", "are", "were", "been",
            "be", "have", "has", "had", "do", "does", "did", "will", "would",
            "could", "should", "may", "might", "must", "shall", "can", "need",
            "this", "that", "these", "those", "i", "you", "he", "she", "it",
            "we", "they", "what", "which", "who", "whom", "how", "when", "where",
            "why", "if", "then", "because", "so", "than", "too", "very", "just",
            "also", "only", "such", "no", "not", "yes", "up", "down", "out", "about",
        ]

        let words =
            text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        // Count frequency
        var frequency: [String: Int] = [:]
        for word in words {
            frequency[word, default: 0] += 1
        }

        // Return top N by frequency
        return
            frequency
            .sorted { $0.value > $1.value }
            .prefix(maxCount)
            .map { $0.key }
    }
}

extension Notification.Name {
    static let afmUserHintNeeded = Notification.Name("com.llmhub.afm.userHintNeeded")
}
