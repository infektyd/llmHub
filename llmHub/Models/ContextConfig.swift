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
        defaultMaxTokens: 120_000, // Conservative default for most models
        preserveSystemPrompt: true,
        preserveRecentMessages: 10,
        providerOverrides: [:]
    )
    
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
