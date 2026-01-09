//
//  ContextConfig.swift
//  llmHub
//
//  Created by AI Assistant on 12/10/25.
//

import Foundation

/// Configuration for context management and compaction behavior.
struct ContextConfig: Codable, Sendable {
    /// Whether automatic context compaction is enabled.
    let enabled: Bool
    /// Whether rolling-summary compaction is enabled.
    ///
    /// Rationale: Rolling summary preserves older context in a compressed form, and avoids
    /// aggressive truncation when conversations grow long.
    let summarizationEnabled: Bool
    /// Trigger rolling-summary compaction once the conversation reaches this number of turns.
    ///
    /// Turn definition: number of `.user` messages.
    let summarizeAtTurnCount: Int
    /// Preserve the last N turns (user messages + their trailing assistant/tool messages).
    let preserveLastTurns: Int
    /// Maximum size of the rolling summary output.
    ///
    /// Interpreted as a token budget heuristic via `TokenEstimator` (best-effort).
    let summaryMaxTokens: Int
    /// The default maximum token limit for conversations.
    let defaultMaxTokens: Int
    /// Whether to always preserve the system prompt during compaction.
    let preserveSystemPrompt: Bool
    /// The number of recent messages to preserve during compaction.
    let preserveRecentMessages: Int
    /// Provider-specific token limit overrides (keyed by provider ID).
    let providerOverrides: [String: Int]

    /// Default configuration with sensible defaults.
    static let `default` = ContextConfig(
        enabled: true,
        summarizationEnabled: true,
        summarizeAtTurnCount: 18,
        preserveLastTurns: 6,
        summaryMaxTokens: 900,
        defaultMaxTokens: 120_000, // Conservative default for most models
        preserveSystemPrompt: true,
        preserveRecentMessages: 10,
        providerOverrides: [:]
    )

    init(
        enabled: Bool,
        summarizationEnabled: Bool,
        summarizeAtTurnCount: Int,
        preserveLastTurns: Int,
        summaryMaxTokens: Int,
        defaultMaxTokens: Int,
        preserveSystemPrompt: Bool,
        preserveRecentMessages: Int,
        providerOverrides: [String: Int]
    ) {
        self.enabled = enabled
        self.summarizationEnabled = summarizationEnabled
        self.summarizeAtTurnCount = summarizeAtTurnCount
        self.preserveLastTurns = preserveLastTurns
        self.summaryMaxTokens = summaryMaxTokens
        self.defaultMaxTokens = defaultMaxTokens
        self.preserveSystemPrompt = preserveSystemPrompt
        self.preserveRecentMessages = preserveRecentMessages
        self.providerOverrides = providerOverrides
    }

    // MARK: - Codable compatibility

    enum CodingKeys: String, CodingKey {
        case enabled
        case summarizationEnabled
        case summarizeAtTurnCount
        case preserveLastTurns
        case summaryMaxTokens
        case defaultMaxTokens
        case preserveSystemPrompt
        case preserveRecentMessages
        case providerOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Back-compat: missing keys should default to current defaults rather than failing decode.
        let defaults = ContextConfig.default

        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        self.summarizationEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .summarizationEnabled)
            ?? defaults.summarizationEnabled
        self.summarizeAtTurnCount =
            try container.decodeIfPresent(Int.self, forKey: .summarizeAtTurnCount)
            ?? defaults.summarizeAtTurnCount
        self.preserveLastTurns =
            try container.decodeIfPresent(Int.self, forKey: .preserveLastTurns)
            ?? defaults.preserveLastTurns
        self.summaryMaxTokens =
            try container.decodeIfPresent(Int.self, forKey: .summaryMaxTokens)
            ?? defaults.summaryMaxTokens
        self.defaultMaxTokens =
            try container.decodeIfPresent(Int.self, forKey: .defaultMaxTokens)
            ?? defaults.defaultMaxTokens
        self.preserveSystemPrompt =
            try container.decodeIfPresent(Bool.self, forKey: .preserveSystemPrompt)
            ?? defaults.preserveSystemPrompt
        self.preserveRecentMessages =
            try container.decodeIfPresent(Int.self, forKey: .preserveRecentMessages)
            ?? defaults.preserveRecentMessages
        self.providerOverrides =
            try container.decodeIfPresent([String: Int].self, forKey: .providerOverrides)
            ?? defaults.providerOverrides
    }

    /// Returns the maximum token limit for a specific provider.
    /// - Parameter providerID: The provider identifier.
    /// - Returns: The token limit, either from overrides or the default.
    func maxTokens(for providerID: String) -> Int {
        providerOverrides[providerID] ?? defaultMaxTokens
    }
}

/// UserDefaults keys for persisting context configuration.
extension UserDefaults {
    private static let contextConfigKey = "com.llmhub.contextConfig"

    /// Saves the context configuration.
    /// - Parameter config: The configuration to save.
    func saveContextConfig(_ config: ContextConfig) {
        if let encoded = try? JSONEncoder().encode(config) {
            set(encoded, forKey: Self.contextConfigKey)
        }
    }

    /// Loads the context configuration.
    /// - Returns: The saved configuration, or the default if none exists.
    func loadContextConfig() -> ContextConfig {
        guard let data = data(forKey: Self.contextConfigKey),
              let config = try? JSONDecoder().decode(ContextConfig.self, from: data) else {
            return .default
        }
        return config
    }
}
