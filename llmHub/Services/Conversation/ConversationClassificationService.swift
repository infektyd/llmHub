//
//  ConversationClassificationService.swift
//  llmHub
//
//  Created by Agent on 12/15/25.
//

import Foundation
import FoundationModels

// MARK: - Classification Types

/// The primary category of a conversation.
nonisolated enum ConversationCategory: String, CaseIterable, Codable, Sendable {
    case coding  // Programming, debugging, code review
    case research  // Information gathering, learning
    case creative  // Writing, brainstorming, design
    case planning  // Project planning, organization
    case support  // Help, troubleshooting, explanations
    case general  // General conversation, misc

    var icon: String {
        switch self {
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .research: return "magnifyingglass"
        case .creative: return "paintbrush"
        case .planning: return "list.bullet.clipboard"
        case .support: return "questionmark.circle"
        case .general: return "bubble.left.and.bubble.right"
        }
    }
}

/// The user's apparent intent for a conversation.
nonisolated enum ConversationIntent: String, CaseIterable, Codable, Sendable {
    case quickQuestion  // Short, one-off query
    case debugging  // Problem-solving session
    case exploration  // Open-ended discussion
    case creation  // Creating content/code
    case reference  // Seeking knowledge to retain

    var displayName: String {
        switch self {
        case .quickQuestion: return "Quick Question"
        case .debugging: return "Debugging"
        case .exploration: return "Exploration"
        case .creation: return "Creation"
        case .reference: return "Reference"
        }
    }
}

/// Suggested retention policy based on content value.
nonisolated enum RetentionPolicy: String, CaseIterable, Codable, Sendable {
    case keep  // Explicitly valuable
    case archive  // Done but may reference
    case reviewIn7Days  // Flag for cleanup review
    case autoDeleteOK  // Low value, safe to purge

    var displayName: String {
        switch self {
        case .keep: return "Keep"
        case .archive: return "Archive"
        case .reviewIn7Days: return "Review Later"
        case .autoDeleteOK: return "Auto-Delete OK"
        }
    }
}

/// Metadata extracted from a conversation by classification.
nonisolated struct ConversationMetadata: Sendable {
    /// A concise title for the conversation (max 50 chars).
    let title: String
    /// A single emoji representing the topic.
    let emoji: String
    /// The primary category.
    let category: ConversationCategory
    /// Key topics discussed (1-5 items).
    let topics: [String]
    /// The user's apparent intent.
    let intent: ConversationIntent
    /// Whether the conversation appears complete/resolved.
    let isComplete: Bool
    /// Whether it contains code, files, or actionable outputs.
    let hasArtifacts: Bool
    /// Suggested retention policy.
    let suggestedRetention: RetentionPolicy

    /// Creates fallback metadata when AFM is unavailable.
    static func fallback(from messages: [ChatMessage]) -> ConversationMetadata {
        let firstUserMessage = messages.first { $0.role == .user }?.content ?? "New Conversation"
        let title = String(firstUserMessage.prefix(50)).trimmingCharacters(
            in: .whitespacesAndNewlines)

        // Simple heuristics for category detection
        let allContent = messages.map { $0.content.lowercased() }.joined(separator: " ")
        let category: ConversationCategory
        if allContent.contains("code") || allContent.contains("function")
            || allContent.contains("error") || allContent.contains("swift")
            || allContent.contains("python") || allContent.contains("javascript") {
            category = .coding
        } else if allContent.contains("how to") || allContent.contains("what is")
            || allContent.contains("explain") {
            category = .research
        } else if allContent.contains("write") || allContent.contains("create")
            || allContent.contains("generate") {
            category = .creative
        } else {
            category = .general
        }

        // Check for artifacts (code blocks)
        let hasArtifacts = messages.contains { !$0.codeBlocks.isEmpty }

        // Simple intent detection
        let intent: ConversationIntent
        if messages.count <= 2 {
            intent = .quickQuestion
        } else if allContent.contains("debug") || allContent.contains("fix")
            || allContent.contains("error") {
            intent = .debugging
        } else {
            intent = .exploration
        }

        // Emoji selection based on category
        let emoji: String
        switch category {
        case .coding: emoji = "💻"
        case .research: emoji = "🔍"
        case .creative: emoji = "✨"
        case .planning: emoji = "📋"
        case .support: emoji = "💡"
        case .general: emoji = "💬"
        }

        return ConversationMetadata(
            title: title.isEmpty ? "New Conversation" : title,
            emoji: emoji,
            category: category,
            topics: [],
            intent: intent,
            isComplete: false,
            hasArtifacts: hasArtifacts,
            suggestedRetention: messages.count <= 2 ? .autoDeleteOK : .reviewIn7Days
        )
    }
}

// MARK: - Classification Service

/// Service for classifying conversations using Apple Foundation Models.
nonisolated final class ConversationClassificationService: Sendable {
    private let keychainStore: KeychainStore
    private let fallbackClassifier: AFMFallbackClassifier

    init(keychainStore: KeychainStore) {
        self.keychainStore = keychainStore
        self.fallbackClassifier = AFMFallbackClassifier(keychainStore: keychainStore)
    }

    @MainActor
    convenience init() {
        self.init(keychainStore: KeychainStore())
    }

    /// Check if AFM is available on this device.
    /// AFM requires macOS 26+ / iOS 26+ with Apple Intelligence enabled.
    var isAvailable: Bool {
        if #available(macOS 15.0, iOS 18.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        return false
    }

    /// Classifies a conversation based on its messages.
    /// Falls back to heuristic classification when AFM is unavailable.
    func classify(messages: [ChatMessage]) async throws -> ConversationMetadata {
        if isAvailable, #available(macOS 15.0, iOS 18.0, *) {
            do {
                return try await classifyWithAFM(messages: messages)
            } catch {
                // Fall through to Gemini fallback and finally heuristics.
            }
        }

        if let gemini = await fallbackClassifier.classify(messages: messages) {
            return gemini
        }

        return ConversationMetadata.fallback(from: messages)
    }

    @available(macOS 15.0, iOS 18.0, *)
    private func classifyWithAFM(messages: [ChatMessage]) async throws -> ConversationMetadata {
        // Build context from first N messages (respect 4K token limit)
        let context = buildClassificationContext(from: messages, maxMessages: 10)

        await FoundationModelsDiagnostics.logRequestStart(useCase: "conversation_classification")
        let start = CFAbsoluteTimeGetCurrent()

        do {
            // Use the SystemLanguageModel for classification
            let model = SystemLanguageModel(useCase: .contentTagging)
            let session = LanguageModelSession(model: model)

            let prompt = """
                Analyze this conversation and provide metadata in JSON format:

                Conversation:
                \(context)

                Respond with JSON containing:
                - title: concise title (max 50 chars)
                - emoji: single emoji representing the topic (choose ONE from this set: 🤖 💬 🤔 💭 🧠 💡 ✨ 🎯 🔍 📊 📈 🧪 🧩 🧰 🔧 ⚙️ 🛠️ 💻 🧑‍💻 🧾 📝 ✍️ 🎨 🎵 📚 🗂️ 🧭 🧱 🛰️ 🌐 🔒 🛡️ 🧯 🚀 🧵 🧷 🔗 ⏱️ ✅ ⚠️ ❌ 🐛 🐍 🦊 🐱 🐙 🌟)
                - category: one of [coding, research, creative, planning, support, general]
                - topics: array of 1-5 key topics
                - intent: one of [quickQuestion, debugging, exploration, creation, reference]
                - isComplete: boolean
                - hasArtifacts: boolean
                - suggestedRetention: one of [keep, archive, reviewIn7Days, autoDeleteOK]
                """

            let response = try await session.respond(to: prompt)

            let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000
            await FoundationModelsDiagnostics.logRequestSuccess(latencyMs: latency)

            // Parse the response - in production, use @Generable for structured output
            return try parseAFMResponse(response.content, messages: messages)
        } catch {
            let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000
            await FoundationModelsDiagnostics.logRequestFail(latencyMs: latency, error: error)
            throw error
        }
    }

    private func buildClassificationContext(from messages: [ChatMessage], maxMessages: Int)
        -> String {
        let relevantMessages = Array(messages.prefix(maxMessages))
        return relevantMessages.map { msg in
            let role = msg.role.rawValue.capitalized
            let content = String(msg.content.prefix(500))
            return "\(role): \(content)"
        }.joined(separator: "\n\n")
    }

    @available(macOS 15.0, iOS 18.0, *)
    private func parseAFMResponse(_ content: String, messages: [ChatMessage]) throws
        -> ConversationMetadata {
        try decodeMetadata(from: content, messages: messages)
    }

    private func decodeMetadata(from content: String, messages: [ChatMessage]) throws -> ConversationMetadata {
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

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            jsonString = String(trimmed[start...end])
        } else {
            jsonString = trimmed
        }

        guard let data = jsonString.data(using: .utf8) else {
            return ConversationMetadata.fallback(from: messages)
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
