//
//  ContextCompactor.swift
//  llmHub
//
//  Actor responsible for compacting chat message history to fit within token limits.
//

import Foundation

actor ContextCompactor {
    
    /// Configuration for a single compaction operation.
    struct CompactionConfig: Sendable {
        let maxTokens: Int
        let preserveSystemPrompt: Bool
        let preserveRecentMessages: Int
        let summaryModel: String?
    }
    
    /// The strategy to use when compacting messages.
    enum CompactionStrategy: Sendable {
        case truncateOldest
        case summarizeOldest // Placeholder for future implementation
    }
    
    /// Compacts messages to fit within the maxTokens limit defined in config.
    /// - Parameters:
    ///   - messages: The array of messages to compact.
    ///   - config: The compaction configuration.
    ///   - strategy: The compaction strategy to use.
    /// - Returns: A `CompactionResult` containing the compacted messages and statistics.
    func compact(
        messages: [ChatMessage],
        config: CompactionConfig,
        strategy: CompactionStrategy = .truncateOldest
    ) async throws -> CompactionResult {
        
        let originalTokens = estimateTokens(messages: messages)
        
        // 1. Check if we are already within the limit
        if originalTokens <= config.maxTokens {
            return CompactionResult(
                compactedMessages: messages,
                droppedCount: 0,
                summaryGenerated: false,
                originalTokens: originalTokens,
                finalTokens: originalTokens
            )
        }
        
        // 2. Identify "Safe" messages that should be preserved if possible
        var safeIndices = Set<Int>()
        let count = messages.count
        
        // A. Preserve System Prompt (first message with role "system")
        if config.preserveSystemPrompt {
            if let systemIndex = messages.firstIndex(where: { $0.role == .system }) {
                safeIndices.insert(systemIndex)
            }
        }
        
        // B. Preserve Recent Messages
        let preserveCount = config.preserveRecentMessages
        let startIndexForRecent = max(0, count - preserveCount)
        for i in startIndexForRecent..<count {
            safeIndices.insert(i)
        }
        
        // 3. Identify droppable messages (middle history)
        // Sort indices to drop oldest first (ascending order)
        let droppableIndices = (0..<count)
            .filter { !safeIndices.contains($0) }
            .sorted()
        
        // 4. Drop messages until we fit in the limit
        var currentTokens = originalTokens
        var droppedIndices = Set<Int>()
        
        for index in droppableIndices {
            if currentTokens <= config.maxTokens {
                break
            }
            
            let message = messages[index]
            // Calculate tokens for this message to subtract
            // Must match TokenEstimator logic: content + overhead
            let messageCost = TokenEstimator.estimate(message.content) + 4
            
            currentTokens -= messageCost
            droppedIndices.insert(index)
        }
        
        // 5. Emergency Compaction (Edge Case)
        // If preserving safe messages (system + recent) still exceeds maxTokens
        if currentTokens > config.maxTokens {
            // Prioritize: System Prompt + Absolute Newest Message
            // Drop everything else
            
            var strictKeepIndices = Set<Int>()
            
            // Keep System Prompt if configured and present
            if config.preserveSystemPrompt, 
               let systemIndex = messages.firstIndex(where: { $0.role == .system }) {
                strictKeepIndices.insert(systemIndex)
            }
            
            // Keep the absolute newest message (last one)
            if let lastIndex = messages.indices.last {
                strictKeepIndices.insert(lastIndex)
            }
            
            // Identify all indices that are NOT strictly kept
            // These will be considered "dropped" relative to the original set
            let allIndices = Set(messages.indices)
            droppedIndices = allIndices.subtracting(strictKeepIndices)
            
            // Recalculate final tokens for the strict set
            let strictMessages = messages.enumerated()
                .filter { strictKeepIndices.contains($0.offset) }
                .map { $0.element }
            
            currentTokens = estimateTokens(messages: strictMessages)
        }
        
        // 6. Construct the result
        // Filter original messages, keeping relative order
        let finalMessages = messages.enumerated()
            .filter { !droppedIndices.contains($0.offset) }
            .map { $0.element }
        
        return CompactionResult(
            compactedMessages: finalMessages,
            droppedCount: droppedIndices.count,
            summaryGenerated: false,
            originalTokens: originalTokens,
            finalTokens: currentTokens
        )
    }
    
    /// Estimates the total token count for an array of messages.
    /// - Parameter messages: The messages to estimate.
    /// - Returns: The estimated token count.
    nonisolated func estimateTokens(messages: [ChatMessage]) -> Int {
        return TokenEstimator.estimate(messages: messages)
    }
}

/// The result of a compaction operation.
struct CompactionResult: Sendable {
    /// The compacted array of messages.
    let compactedMessages: [ChatMessage]
    /// The number of messages that were dropped.
    let droppedCount: Int
    /// Whether a summary was generated (for future summarization strategy).
    let summaryGenerated: Bool
    /// The original token count before compaction.
    let originalTokens: Int
    /// The final token count after compaction.
    let finalTokens: Int
}
