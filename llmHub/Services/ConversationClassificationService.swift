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
enum ConversationCategory: String, CaseIterable, Codable, Sendable {
    case coding = "coding"  // Programming, debugging, code review
    case research = "research"  // Information gathering, learning
    case creative = "creative"  // Writing, brainstorming, design
    case planning = "planning"  // Project planning, organization
    case support = "support"  // Help, troubleshooting, explanations
    case general = "general"  // General conversation, misc

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
enum ConversationIntent: String, CaseIterable, Codable, Sendable {
    case quickQuestion = "quickQuestion"  // Short, one-off query
    case debugging = "debugging"  // Problem-solving session
    case exploration = "exploration"  // Open-ended discussion
    case creation = "creation"  // Creating content/code
    case reference = "reference"  // Seeking knowledge to retain

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
enum RetentionPolicy: String, CaseIterable, Codable, Sendable {
    case keep = "keep"  // Explicitly valuable
    case archive = "archive"  // Done but may reference
    case reviewIn7Days = "reviewIn7Days"  // Flag for cleanup review
    case autoDeleteOK = "autoDeleteOK"  // Low value, safe to purge

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
struct ConversationMetadata: Sendable {
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
            || allContent.contains("python") || allContent.contains("javascript")
        {
            category = .coding
        } else if allContent.contains("how to") || allContent.contains("what is")
            || allContent.contains("explain")
        {
            category = .research
        } else if allContent.contains("write") || allContent.contains("create")
            || allContent.contains("generate")
        {
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
            || allContent.contains("error")
        {
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
@MainActor
final class ConversationClassificationService {
    private let keychainStore: KeychainStore

    init(keychainStore: KeychainStore = KeychainStore()) {
        self.keychainStore = keychainStore
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
        if let gemini = try await classifyWithGemini(messages: messages) {
            return gemini
        }

        guard isAvailable else { return ConversationMetadata.fallback(from: messages) }

        if #available(macOS 15.0, iOS 18.0, *) {
            do {
                return try await classifyWithAFM(messages: messages)
            } catch {
                return ConversationMetadata.fallback(from: messages)
            }
        }

        return ConversationMetadata.fallback(from: messages)
    }

    @available(macOS 15.0, iOS 18.0, *)
    private func classifyWithAFM(messages: [ChatMessage]) async throws -> ConversationMetadata {
        // Build context from first N messages (respect 4K token limit)
        let context = buildClassificationContext(from: messages, maxMessages: 10)

        FoundationModelsDiagnostics.logRequestStart(useCase: "conversation_classification")
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
                - emoji: single emoji representing the topic
                - category: one of [coding, research, creative, planning, support, general]
                - topics: array of 1-5 key topics
                - intent: one of [quickQuestion, debugging, exploration, creation, reference]
                - isComplete: boolean
                - hasArtifacts: boolean
                - suggestedRetention: one of [keep, archive, reviewIn7Days, autoDeleteOK]
                """

            let response = try await session.respond(to: prompt)

            let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000
            FoundationModelsDiagnostics.logRequestSuccess(latencyMs: latency)

            // Parse the response - in production, use @Generable for structured output
            return try parseAFMResponse(response.content, messages: messages)
        } catch {
            let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000
            FoundationModelsDiagnostics.logRequestFail(latencyMs: latency, error: error)
            throw error
        }
    }

    private func buildClassificationContext(from messages: [ChatMessage], maxMessages: Int)
        -> String
    {
        let relevantMessages = Array(messages.prefix(maxMessages))
        return relevantMessages.map { msg in
            let role = msg.role.rawValue.capitalized
            let content = String(msg.content.prefix(500))
            return "\(role): \(content)"
        }.joined(separator: "\n\n")
    }

    @available(macOS 15.0, iOS 18.0, *)
    private func parseAFMResponse(_ content: String, messages: [ChatMessage]) throws
        -> ConversationMetadata
    {
        decodeMetadata(from: content, messages: messages)
    }

    private func classifyWithGemini(messages: [ChatMessage]) async throws -> ConversationMetadata? {
        guard let apiKey = await keychainStore.apiKey(for: .google), !apiKey.isEmpty else {
            return nil
        }

        guard #available(iOS 26.1, macOS 26.1, *) else { return nil }

        let context = buildClassificationContext(from: messages, maxMessages: 12)
        let prompt = """
        Classify this conversation. Return ONLY valid JSON (no backticks, no prose):
        {
          "title": "<max 50 chars>",
          "emoji": "<single emoji>",
          "category": "<coding|research|creative|planning|support|general>",
          "topics": ["topic1", "topic2"],
          "intent": "<quickQuestion|debugging|exploration|creation|reference>",
          "isComplete": <true|false>,
          "hasArtifacts": <true|false>,
          "suggestedRetention": "<keep|archive|reviewIn7Days|autoDeleteOK>"
        }

        Conversation:
        \(context)
        """

        do {
            let manager = GeminiManager(apiKey: apiKey)
            let response = try await manager.generateContent(
                prompt: prompt,
                model: "gemini-2.0-flash"
            )
            let text = response.text ?? ""
            let metadata = decodeMetadata(from: text, messages: messages)
            return metadata
        } catch {
            return nil
        }
    }

    private func decodeMetadata(from content: String, messages: [ChatMessage]) -> ConversationMetadata {
        guard let data = extractJSONData(from: content) else {
            return ConversationMetadata.fallback(from: messages)
        }

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
            let title =
                decoded.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ConversationMetadata.fallback(from: messages).title
            let emoji = decoded.emoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "💬"

            let category = ConversationCategory(rawValue: decoded.category ?? "") ?? .general
            let intent = ConversationIntent(rawValue: decoded.intent ?? "") ?? .exploration
            let topics = decoded.topics ?? []
            let isComplete = decoded.isComplete ?? false
            let hasArtifacts = decoded.hasArtifacts ?? messages.contains { !$0.codeBlocks.isEmpty }

            let retentionRaw = decoded.suggestedRetention ?? decoded.retention ?? RetentionPolicy.reviewIn7Days.rawValue
            let retention = RetentionPolicy(rawValue: retentionRaw) ?? .reviewIn7Days

            return ConversationMetadata(
                title: String(title.prefix(50)),
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

    private func extractJSONData(from content: String) -> Data? {
        guard let jsonStart = content.firstIndex(of: "{"),
            let jsonEnd = content.lastIndex(of: "}")
        else { return nil }
        let jsonString = String(content[jsonStart...jsonEnd])
        return jsonString.data(using: .utf8)
    }
}
