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
        let summarizationEnabled: Bool
        let summarizeAtTurnCount: Int
        let preserveLastTurns: Int
        let summaryMaxTokens: Int
    }
    
    /// The strategy to use when compacting messages.
    enum CompactionStrategy: Sendable {
        case truncateOldest
        case summarizeOldest
    }

    typealias RollingSummaryGenerator =
        @Sendable @MainActor (_ messagesToSummarize: [ChatMessage], _ summaryMaxTokens: Int) async throws -> String
    
    /// Compacts messages to fit within the maxTokens limit defined in config.
    /// - Parameters:
    ///   - messages: The array of messages to compact.
    ///   - config: The compaction configuration.
    ///   - strategy: The compaction strategy to use.
    /// - Returns: A `CompactionResult` containing the compacted messages and statistics.
    func compact(
        messages: [ChatMessage],
        config: CompactionConfig,
        strategy: CompactionStrategy = .truncateOldest,
        rollingSummaryGenerator: RollingSummaryGenerator? = nil
    ) async throws -> CompactionResult {
        
        let originalTokens = estimateTokens(messages: messages)

        // 0. Optional rolling summary: can run even when already under budget (turn-trigger).
        if strategy == .summarizeOldest,
            config.summarizationEnabled,
            let generator = rollingSummaryGenerator
        {
            let turnCount = Self.turnCount(messages: messages)
            let shouldSummarize = (turnCount >= config.summarizeAtTurnCount)
                || (originalTokens > config.maxTokens)

            if shouldSummarize {
                do {
                    let summarized = try await summarizeOldest(
                        messages: messages,
                        config: config,
                        rollingSummaryGenerator: generator
                    )

                    // If summarization did not materially change anything, fall through to normal logic.
                    if summarized.summaryGenerated {
                        // If still too large, fall back to truncation (must never break fallback).
                        if summarized.finalTokens > config.maxTokens {
                            let truncated = try await compact(
                                messages: summarized.compactedMessages,
                                config: config,
                                strategy: .truncateOldest,
                                rollingSummaryGenerator: nil
                            )
                            return CompactionResult(
                                compactedMessages: truncated.compactedMessages,
                                droppedCount: summarized.droppedCount + truncated.droppedCount,
                                summaryGenerated: true,
                                originalTokens: originalTokens,
                                finalTokens: truncated.finalTokens
                            )
                        }
                        return CompactionResult(
                            compactedMessages: summarized.compactedMessages,
                            droppedCount: summarized.droppedCount,
                            summaryGenerated: true,
                            originalTokens: originalTokens,
                            finalTokens: summarized.finalTokens
                        )
                    }
                } catch {
                    // Fallback to truncation on summarization failures.
                }
            }
        }
        
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

    // MARK: - Rolling Summary

    private func summarizeOldest(
        messages: [ChatMessage],
        config: CompactionConfig,
        rollingSummaryGenerator: RollingSummaryGenerator
    ) async throws -> CompactionResult {
        guard !messages.isEmpty else {
            return CompactionResult(
                compactedMessages: messages,
                droppedCount: 0,
                summaryGenerated: false,
                originalTokens: 0,
                finalTokens: 0
            )
        }

        let originalTokens = estimateTokens(messages: messages)

        // Preserve: the first system message (always) + the last N turns.
        let systemIndex = messages.firstIndex(where: { $0.role == .system })
        let tailStartIndex = Self.startIndexForLastTurns(
            messages: messages,
            preserveLastTurns: max(0, config.preserveLastTurns)
        )

        // Determine the range to summarize (exclude system + preserved tail).
        let summarizeStart = (systemIndex.map { $0 + 1 } ?? 0)
        let summarizeEndExclusive = max(summarizeStart, tailStartIndex)
        guard summarizeEndExclusive > summarizeStart else {
            // Nothing to summarize.
            return CompactionResult(
                compactedMessages: messages,
                droppedCount: 0,
                summaryGenerated: false,
                originalTokens: originalTokens,
                finalTokens: originalTokens
            )
        }

        let messagesToSummarize = Array(messages[summarizeStart..<summarizeEndExclusive])
        guard !messagesToSummarize.isEmpty else {
            return CompactionResult(
                compactedMessages: messages,
                droppedCount: 0,
                summaryGenerated: false,
                originalTokens: originalTokens,
                finalTokens: originalTokens
            )
        }

        let rawSummary = try await rollingSummaryGenerator(messagesToSummarize, config.summaryMaxTokens)
        let summary = Self.trimToTokenBudget(text: rawSummary, maxTokens: config.summaryMaxTokens)
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return CompactionResult(
                compactedMessages: messages,
                droppedCount: 0,
                summaryGenerated: false,
                originalTokens: originalTokens,
                finalTokens: originalTokens
            )
        }

        var out: [ChatMessage] = []
        out.reserveCapacity(1 + (messages.count - (summarizeEndExclusive - summarizeStart)))

        // Ensure rolling summary lives in the FIRST system message, so compaction safe indices and
        // providers (Anthropic) that use a single system field won't drop it.
        if let systemIndex, systemIndex < messages.count {
            var system = messages[systemIndex]
            system.content = Self.upsertRollingSummary(into: system.content, summary: summary)
            out.append(system)
        } else {
            let system = ChatMessage(
                id: UUID(),
                role: .system,
                content: Self.upsertRollingSummary(into: "", summary: summary),
                parts: [],
                createdAt: Date(),
                codeBlocks: []
            )
            out.append(system)
        }

        // Append preserved tail (everything from tailStartIndex onward, excluding duplicate system).
        if tailStartIndex < messages.count {
            let tail = Array(messages[tailStartIndex..<messages.count]).filter { $0.role != .system }
            out.append(contentsOf: tail)
        }

        let finalTokens = estimateTokens(messages: out)
        let droppedCount = messages.count - out.count
        return CompactionResult(
            compactedMessages: out,
            droppedCount: max(0, droppedCount),
            summaryGenerated: true,
            originalTokens: originalTokens,
            finalTokens: finalTokens
        )
    }

    private static func startIndexForLastTurns(messages: [ChatMessage], preserveLastTurns: Int) -> Int {
        guard preserveLastTurns > 0 else { return messages.count }
        var remaining = preserveLastTurns
        var idx = messages.count - 1

        // Walk backwards looking for `.user` messages; when we have found N, keep from that index.
        while idx >= 0 {
            if messages[idx].role == .user {
                remaining -= 1
                if remaining == 0 {
                    return idx
                }
            }
            idx -= 1
        }
        return 0
    }

    private static func turnCount(messages: [ChatMessage]) -> Int {
        messages.reduce(into: 0) { acc, msg in
            if msg.role == .user { acc += 1 }
        }
    }

    private static func trimToTokenBudget(text: String, maxTokens: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard maxTokens > 0 else { return "" }
        if TokenEstimator.estimate(trimmed) <= maxTokens { return trimmed }

        // Best-effort truncation by characters, then tighten until token estimate fits.
        var candidate = String(trimmed.prefix(max(200, min(trimmed.count, maxTokens * 4))))
        while !candidate.isEmpty && TokenEstimator.estimate(candidate) > maxTokens {
            candidate = String(candidate.dropLast(max(1, candidate.count / 10)))
        }
        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let rollingSummaryStartTag = "<rolling_summary>"
    private static let rollingSummaryEndTag = "</rolling_summary>"

    private static func upsertRollingSummary(into systemPrompt: String, summary: String) -> String {
        let block = "\(rollingSummaryStartTag)\n\(summary)\n\(rollingSummaryEndTag)"

        // Replace existing block if present.
        if let startRange = systemPrompt.range(of: rollingSummaryStartTag),
            let endRange = systemPrompt.range(of: rollingSummaryEndTag, range: startRange.upperBound..<systemPrompt.endIndex)
        {
            var out = systemPrompt
            out.replaceSubrange(startRange.lowerBound..<endRange.upperBound, with: block)
            return out
        }

        if systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return block
        }

        // Prepend so it stays near the top of the system prompt.
        return "\(block)\n\n\(systemPrompt)"
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
