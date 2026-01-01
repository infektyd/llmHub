//
//  ContextManagementService.swift
//  llmHub
//
//  Service layer for managing context compaction in chat sessions.
//

import Foundation
import OSLog

/// Service responsible for managing context compaction operations.
@MainActor
final class ContextManagementService {
    private let compactor = ContextCompactor()
    private var config: ContextConfig
    private let logger = Logger(subsystem: "com.llmhub", category: "ContextManagement")

    typealias RollingSummaryGenerator =
        @Sendable @MainActor (_ messagesToSummarize: [ChatMessage], _ summaryMaxTokens: Int) async throws -> String
    
    /// Initializes a new context management service.
    /// - Parameter config: The configuration to use. Defaults to loading from UserDefaults.
    init(config: ContextConfig? = nil) {
        self.config = config ?? UserDefaults.standard.loadContextConfig()
    }
    
    /// Updates the configuration and persists it.
    /// - Parameter config: The new configuration.
    func updateConfig(_ config: ContextConfig) {
        self.config = config
        UserDefaults.standard.saveContextConfig(config)
        logger.info("Context configuration updated: enabled=\(config.enabled), maxTokens=\(config.defaultMaxTokens)")
    }
    
    /// Compacts messages to fit within the specified token limit.
    /// - Parameters:
    ///   - messages: The messages to compact.
    ///   - maxTokens: The maximum token limit.
    ///   - providerID: Optional provider ID for provider-specific token limits.
    /// - Returns: A `CompactionResult` containing the compacted messages and statistics.
    func compact(
        messages: [ChatMessage],
        maxTokens: Int? = nil,
        providerID: String? = nil,
        rollingSummaryGenerator: RollingSummaryGenerator? = nil
    ) async throws -> CompactionResult {
        // Check if compaction is enabled
        guard config.enabled else {
            logger.debug("Context compaction disabled, returning original messages")
            let tokens = compactor.estimateTokens(messages: messages)
            return CompactionResult(
                compactedMessages: messages,
                droppedCount: 0,
                summaryGenerated: false,
                originalTokens: tokens,
                finalTokens: tokens
            )
        }
        
        // Determine the token limit to use
        let effectiveMaxTokens: Int
        if let maxTokens = maxTokens {
            effectiveMaxTokens = maxTokens
        } else if let providerID = providerID {
            effectiveMaxTokens = config.maxTokens(for: providerID)
        } else {
            effectiveMaxTokens = config.defaultMaxTokens
        }
        
        // Create compaction configuration
        let compactionConfig = ContextCompactor.CompactionConfig(
            maxTokens: effectiveMaxTokens,
            preserveSystemPrompt: config.preserveSystemPrompt,
            preserveRecentMessages: config.preserveRecentMessages,
            summarizationEnabled: config.summarizationEnabled,
            summarizeAtTurnCount: config.summarizeAtTurnCount,
            preserveLastTurns: config.preserveLastTurns,
            summaryMaxTokens: config.summaryMaxTokens
        )
        
        logger.debug("Starting compaction: \(messages.count) messages, maxTokens=\(effectiveMaxTokens)")
        
        // Perform compaction
        //
        // Rationale: Rolling-summary compaction is optionally enabled. It runs via a dedicated
        // "summarize mode" generator that must not re-enter the normal ChatService agent loop.
        let result = try await compactor.compact(
            messages: messages,
            config: compactionConfig,
            strategy: (config.summarizationEnabled && rollingSummaryGenerator != nil)
                ? .summarizeOldest
                : .truncateOldest,
            rollingSummaryGenerator: rollingSummaryGenerator
        )
        
        if result.droppedCount > 0 {
            logger.info("Context compacted: dropped \(result.droppedCount) messages, saved \(result.originalTokens - result.finalTokens) tokens")
        } else {
            logger.debug("No compaction needed: \(result.originalTokens) tokens within limit")
        }
        
        return result
    }
    
    /// Estimates the token count for a list of messages without performing compaction.
    /// - Parameter messages: The messages to estimate.
    /// - Returns: The estimated token count.
    func estimateTokens(messages: [ChatMessage]) -> Int {
        TokenEstimator.estimate(messages: messages)
    }
    
    /// Returns the current configuration.
    var currentConfig: ContextConfig {
        config
    }
}
