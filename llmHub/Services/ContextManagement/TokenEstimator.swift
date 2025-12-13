//
//  TokenEstimator.swift
//  llmHub
//
//  Provides heuristic-based token estimation for chat messages.
//

import Foundation

struct TokenEstimator: Sendable {
    enum Tokenizer: Sendable {
        case cl100k_base
        case approximate
    }
    
    /// Estimates tokens for a string of text.
    /// Uses a heuristic of ~4 characters per token for the .approximate strategy.
    /// - Parameters:
    ///   - text: The text to estimate.
    ///   - tokenizer: The tokenizer to use (default: approximate).
    /// - Returns: The estimated token count.
    nonisolated static func estimate(_ text: String, tokenizer: Tokenizer = .approximate) -> Int {
        if text.isEmpty { return 0 }
        // Heuristic: 1 token ~= 4 chars. Ensure at least 1 token if not empty.
        return max(1, text.count / 4)
    }
    
    /// Estimates total tokens for a list of messages, including protocol overhead.
    /// - Parameters:
    ///   - messages: The messages to estimate.
    ///   - tokenizer: The tokenizer to use (default: approximate).
    /// - Returns: The total estimated token count.
    nonisolated static func estimate(messages: [ChatMessage], tokenizer: Tokenizer = .approximate) -> Int {
        // Protocol overhead: ~4 tokens per message (role + formatting structure)
        // This makes the estimate more realistic for API limits.
        let messageOverhead = 4
        
        return messages.reduce(0) { total, message in
            total + estimate(message.content, tokenizer: tokenizer) + messageOverhead
        }
    }
}