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

#if canImport(FoundationModels)
    import FoundationModels
#endif

private let logger = AppLogger.category("Memory")

/// Service for distilling conversations into persistent memories using Apple Foundation Models.
/// Runs in background, non-blocking, with graceful fallback when AFM is unavailable.
@MainActor
final class ConversationDistillationService {

    private static var loggedGeminiFallbackSessions: Set<UUID> = []
    private static var loggedMemoryWriteSkips: Set<UUID> = []

    private let keyProvider: APIKeyProviding
    private let geminiJSONGenerator: (@Sendable (_ prompt: String, _ model: String, _ temperature: Double) async throws -> String)?
    private let afmAvailabilityOverride: (@Sendable () -> Bool)?

    init(
        keyProvider: APIKeyProviding = KeychainStore(),
        geminiJSONGenerator: (@Sendable (_ prompt: String, _ model: String, _ temperature: Double) async throws -> String)? = nil,
        afmAvailabilityOverride: (@Sendable () -> Bool)? = nil
    ) {
        self.keyProvider = keyProvider
        self.geminiJSONGenerator = geminiJSONGenerator
        self.afmAvailabilityOverride = afmAvailabilityOverride
    }

    // MARK: - Configuration

    /// Maximum messages to consider for distillation (token budget safety).
    private static let maxMessagesForDistillation = 15
    /// Minimum messages required to warrant distillation.
    private static let minMessagesForDistillation = 3
    /// Maximum token budget for AFM input context.
    private static let maxContextTokens = 4096

    // MARK: - Availability

    /// Check if AFM is available on this device.
    var isAvailable: Bool {
        if let afmAvailabilityOverride {
            return afmAvailabilityOverride()
        }
        #if canImport(FoundationModels)
            if #available(macOS 26.0, iOS 26.0, *) {
                // IMPORTANT: do not attempt any AFM/local prewarm path when Apple Intelligence is disabled.
                return SystemLanguageModel.default.availability == .available
            }
            return false
        #else
            return false
        #endif
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
        if Task.isCancelled {
            logger.debug("Skipping distillation for session \(sessionID): cancelled")
            return
        }

        // Guard: Skip if too few messages
        guard messages.count >= Self.minMessagesForDistillation else {
            logger.debug(
                "Skipping distillation for session \(sessionID): too few messages (\(messages.count))"
            )
            return
        }

        if Task.isCancelled {
            logger.debug("Skipping distillation for session \(sessionID): cancelled")
            return
        }

        // If AFM is unavailable, fall back to Gemini HTTP. Persist into the app memory store,
        // but mark as sidecar so it is never injected into chat prompting.
        if !isAvailable {
            if Task.isCancelled {
                logger.debug("Skipping distillation for session \(sessionID): cancelled")
                return
            }
            logger.info("Distillation path: AFM unavailable → Gemini HTTP (session=\(sessionID))")
            if let memory = await distillWithGeminiFallback(
                messages: messages,
                providerID: providerID,
                sessionID: sessionID
            ) {
                do {
                    try persist(
                        memory: memory,
                        modelContext: modelContext,
                        provenance: .sidecar(model: GeminiPinnedModels.afmFallbackFlash)
                    )
                } catch {
                    logger.error("Failed to persist Gemini distillation memory (session=\(sessionID)): \(error.localizedDescription)")
                }
            }
            return
        }

        logger.info("Distillation path: AFM available → AFM local model (session=\(sessionID))")

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
            #if canImport(FoundationModels)
                if #available(macOS 26.0, iOS 26.0, *) {
                    let memory = try await distillWithAFM(
                        messages: truncated,
                        providerID: providerID,
                        sessionID: sessionID
                    )
                    // Persist into the app memory store, but mark as sidecar so it is never injected into chat prompting.
                    try persist(
                        memory: memory,
                        modelContext: modelContext,
                        provenance: .sidecar(model: "afm")
                    )
                } else {
                    logger.debug("Skipping distillation for session \(sessionID): unsupported OS")
                }
            #else
                logger.debug("Skipping distillation for session \(sessionID): FoundationModels unavailable")
            #endif
        } catch {
            if error is CancellationError {
                logger.debug("Skipping distillation for session \(sessionID): cancelled")
                return
            }

            // AFM failed at runtime; attempt fixed remote Gemini fallback.
            logger.info("Distillation path: AFM failed → Gemini HTTP (session=\(sessionID))")
            if let memory = await distillWithGeminiFallback(
                messages: truncated,
                providerID: providerID,
                sessionID: sessionID
            ) {
                do {
                    try persist(
                        memory: memory,
                        modelContext: modelContext,
                        provenance: .sidecar(model: GeminiPinnedModels.afmFallbackFlash)
                    )
                } catch {
                    logger.error("Failed to persist Gemini distillation memory after AFM failure (session=\(sessionID)): \(error.localizedDescription)")
                }
            }

            logger.error("Distillation failed for session \(sessionID): \(error.localizedDescription)")
        }
    }

    // MARK: - Fixed Remote Fallback (Gemini)

    private func distillWithGeminiFallback(
        messages: [ChatMessage],
        providerID: String,
        sessionID: UUID
    ) async -> Memory? {
        if Task.isCancelled { return nil }
        guard let apiKey = await keyProvider.apiKey(for: .google), !apiKey.isEmpty else {
            return nil
        }

        // Log once per session to avoid background spam.
        if !Self.loggedGeminiFallbackSessions.contains(sessionID) {
            Self.loggedGeminiFallbackSessions.insert(sessionID)
            logger.info("AFM unavailable/failed → using Gemini Flash fallback for distillation")
        }

        let context = buildDistillationContext(from: messages)
        let prompt = """
        Distill this conversation into a structured essence for future retrieval.

        CONVERSATION:
        \(context)

        OUTPUT:
        Return ONLY valid JSON with this exact schema:
        {
          "summary": string,
          "userFacts": [{"statement": string, "category": string}],
          "preferences": [{"topic": string, "value": string}],
          "decisions": [{"decision": string, "context": string}],
          "artifacts": [{"type": string, "description": string, "language": string|null}],
          "keywords": [string]
        }

        REQUIREMENTS:
        - summary: concise 1-2 sentences.
        - userFacts: max 5.
        - preferences: max 5.
        - decisions: max 3.
        - artifacts: max 3.
        - keywords: 10-20 items, STRICT MAX 20.
        """

        do {
            let jsonText: String

            if let geminiJSONGenerator {
                logger.info(
                    "Gemini distillation request (injected generator): model=\(GeminiPinnedModels.afmFallbackFlash) host=generativelanguage.googleapis.com maxOutputTokens=1024 temperature=\(GeminiPinnedModels.afmFallbackTemperature)"
                )
                jsonText = try await geminiJSONGenerator(
                    prompt,
                    GeminiPinnedModels.afmFallbackFlash,
                    GeminiPinnedModels.afmFallbackTemperature
                )
            } else {
                guard #available(iOS 26.1, macOS 26.1, *) else { return nil }

                // Build a direct HTTP request (no tools) to avoid any Apple/local-model pathways.
                // This must go to generativelanguage.googleapis.com.
                let manager = GeminiManager(apiKey: apiKey)
                let maxOutputTokens = 1024
                let request = try manager.makeGenerateContentRequest(
                    prompt: prompt,
                    files: [],
                    model: GeminiPinnedModels.afmFallbackFlash,
                    temperature: Float(GeminiPinnedModels.afmFallbackTemperature),
                    thinkingLevel: .off,
                    history: [],
                    tools: nil,
                    maxOutputTokens: maxOutputTokens,
                    responseMimeType: "application/json",
                    stream: false
                )

                let host = request.url?.host ?? "(unknown)"
                logger.info(
                    "Gemini distillation request built: model=\(GeminiPinnedModels.afmFallbackFlash) host=\(host) maxOutputTokens=\(maxOutputTokens)"
                )

                let started = Date()
                logger.debug("Gemini distillation request sending (session=\(sessionID))")
                let (data, response) = try await LLMURLSession.data(for: request)
                let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.info(
                    "Gemini distillation request finished: status=\(status) elapsedMs=\(elapsedMs) bytes=\(data.count) (session=\(sessionID))"
                )

                let decoded = try JSONDecoder().decode(GenerationResponse.self, from: data)
                jsonText = decoded.text ?? ""
            }

            if Task.isCancelled { return nil }
            guard let data = jsonText.data(using: .utf8) else { return nil }

            let decoded = try JSONDecoder().decode(FallbackEssence.self, from: data)

            return Memory(
                providerID: providerID,
                summary: decoded.summary,
                userFacts: Array(decoded.userFacts.prefix(5)),
                preferences: Array(decoded.preferences.prefix(5)),
                decisions: Array(decoded.decisions.prefix(3)),
                artifacts: Array(decoded.artifacts.prefix(3)),
                keywords: Array(decoded.keywords.prefix(20)),
                isComplete: true,
                confidence: 0.75,
                sourceSessionID: sessionID
            )
        } catch {
            if error is CancellationError { return nil }
            return nil
        }
    }

    // MARK: - AFM Distillation

    #if canImport(FoundationModels)
        @available(macOS 26.0, iOS 26.0, *)
        private func distillWithAFM(
            messages: [ChatMessage],
            providerID: String,
            sessionID: UUID
        ) async throws -> Memory {
            // Build context from messages (already token-aware truncated in caller)
            let context = buildDistillationContext(from: messages)

            let prompt = """
                Distill this conversation into a structured essence for future retrieval.

                CONVERSATION:
                \(context)

                REQUIREMENTS:
                - summary: concise 1-2 sentences.
                - userFacts: max 5.
                - preferences: max 5.
                - decisions: max 3.
                - artifacts: max 3.
                - keywords: 10-20 keywords (max 20) suitable for retrieval.
                """

            // Phase 2: use SystemLanguageModel content tagging adapter.
            let model = SystemLanguageModel(useCase: .contentTagging)
            let session = LanguageModelSession(model: model)
            let response = try await session.respond(to: prompt, generating: ConversationEssence.self)
            let essence = response.content

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
                    FallbackArtifact(type: $0.type, description: $0.description, language: $0.language)
                },
                keywords: Array(essence.keywords.prefix(20)),
                isComplete: true,
                confidence: 0.9,
                sourceSessionID: sessionID
            )
        }
    #endif

    // MARK: - Helpers

    private func buildDistillationContext(from messages: [ChatMessage]) -> String {
        messages.map { msg in
            let role = msg.role.rawValue.capitalized
            let content = String(msg.content.prefix(1200))
            return "\(role): \(content)"
        }.joined(separator: "\n\n")
    }

    private func truncateForDistillation(messages: [ChatMessage]) -> [ChatMessage] {
        guard !messages.isEmpty else { return [] }

        var candidate = Array(messages.suffix(Self.maxMessagesForDistillation))

        while candidate.count > Self.minMessagesForDistillation {
            let context = buildDistillationContext(from: candidate)
            let estimated = TokenEstimator.estimate(context)
            if estimated <= Self.maxContextTokens {
                break
            }
            candidate.removeFirst()
        }

        return candidate
    }

    private func partialMemory(from messages: [ChatMessage], providerID: String, sessionID: UUID) -> Memory {
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

    private func persist(
        memory: Memory,
        modelContext: ModelContext,
        provenance: MessageProvenance
    ) throws {
        let entity = MemoryEntity(memory: memory, provenance: provenance)
        modelContext.insert(entity)
        try modelContext.save()
        entity.logCreation()
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
