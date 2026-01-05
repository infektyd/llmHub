//
//  AFMFallbackClassifier.swift
//  llmHub
//
//  Gemini 2.0 Flash fallback classifier for conversation metadata.
//

import Foundation

/// Gemini-based fallback when Apple Foundation Models (AFM) are unavailable or fail.
/// Uses native JSON mode via `responseMimeType = application/json`.
nonisolated struct AFMFallbackClassifier: Sendable {
    private let keychainStore: KeychainStore

    init(keychainStore: KeychainStore) {
        self.keychainStore = keychainStore
    }

    @MainActor
    init() {
        self.init(keychainStore: KeychainStore())
    }

    /// Attempts classification using Gemini 2.0 Flash.
    /// - Returns: `nil` if no Gemini API key is available or the platform doesn't support GeminiManager.
    func classify(messages: [ChatMessage]) async -> ConversationMetadata? {
        guard let apiKey = await keychainStore.apiKey(for: .google), !apiKey.isEmpty else {
            return nil
        }

        guard #available(iOS 26.1, macOS 26.1, *) else {
            return nil
        }

        let prompt = buildPrompt(messages: messages)

        do {
            let manager = await MainActor.run { GeminiManager(apiKey: apiKey) }
            let response = try await manager.generateContent(
                prompt: prompt,
                model: "gemini-2.0-flash",
                responseMimeType: "application/json"
            )

            let text = response.text ?? ""
            guard let data = text.data(using: .utf8) else { return nil }

            return decodeMetadata(from: data, messages: messages)
        } catch {
            return nil
        }
    }

    private func buildPrompt(messages: [ChatMessage]) -> String {
        let context = buildClassificationContext(from: messages, maxMessages: 12)
        return """
        Analyze this conversation and extract metadata.

        Fields to extract:
        - title (max 50 chars)
        - emoji (single emoji)
        - category (coding|research|creative|planning|support|general)
        - topics (0-5 items)
        - intent (quickQuestion|debugging|exploration|creation|reference)
        - isComplete (true|false)
        - hasArtifacts (true|false)
        - suggestedRetention (keep|archive|reviewIn7Days|autoDeleteOK)

        Conversation:
        \(context)
        """
    }

    private func buildClassificationContext(from messages: [ChatMessage], maxMessages: Int) -> String {
        let relevantMessages = Array(messages.prefix(maxMessages))
        return relevantMessages.map { msg in
            let role = msg.role.rawValue.capitalized
            let content = String(msg.content.prefix(500))
            return "\(role): \(content)"
        }.joined(separator: "\n\n")
    }

    private func decodeMetadata(from data: Data, messages: [ChatMessage]) -> ConversationMetadata {
        struct LLMResponse: Decodable {
            let title: String?
            let emoji: String?
            let category: String?
            let topics: [String]?
            let intent: String?
            let isComplete: Bool?
            let hasArtifacts: Bool?
            let suggestedRetention: String?
            let retention: String?
        }

        do {
            let decoded = try JSONDecoder().decode(LLMResponse.self, from: data)

            let fallback = ConversationMetadata.fallback(from: messages)

            let title = (decoded.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
                $0.isEmpty ? nil : String($0.prefix(50))
            } ?? fallback.title

            let emoji = (decoded.emoji?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
                $0.isEmpty ? nil : $0
            } ?? fallback.emoji

            let category = ConversationCategory(rawValue: decoded.category ?? "") ?? fallback.category
            let intent = ConversationIntent(rawValue: decoded.intent ?? "") ?? fallback.intent
            let topics = decoded.topics ?? []
            let isComplete = decoded.isComplete ?? fallback.isComplete
            let hasArtifacts = decoded.hasArtifacts ?? fallback.hasArtifacts

            let retentionRaw = decoded.suggestedRetention ?? decoded.retention
            let retention = RetentionPolicy(rawValue: retentionRaw ?? "") ?? fallback.suggestedRetention

            return ConversationMetadata(
                title: title,
                emoji: emoji,
                category: category,
                topics: topics,
                intent: intent,
                isComplete: isComplete,
                hasArtifacts: hasArtifacts,
                suggestedRetention: retention
            )
        } catch {
            return ConversationMetadata.fallback(from: messages)
        }
    }
}
