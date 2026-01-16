//
//  MessageSequenceValidator.swift
//  llmHub
//
//  Validates and sanitizes message sequences for LLM API compliance.
//  Specifically targets Mistral API's strict message ordering requirements.
//
//  Key constraints enforced:
//  - Tool role messages must have a corresponding prior assistant message with toolCallID
//  - Tool role messages must immediately follow their parent assistant message
//  - Empty trailing assistant messages are removed
//
//  FAIL-OPEN: Invalid messages are dropped with warnings; never crashes, never modifies persisted history.
//

import Foundation
import OSLog

/// Validates and sanitizes chat message sequences for API compliance.
struct MessageSequenceValidator: Sendable {
    
    private static let logger = Logger(subsystem: "com.llmhub", category: "MessageSequence")
    
    // MARK: - Validation Result
    
    struct ValidationResult: Sendable {
        /// The sanitized messages ready for API submission.
        let sanitizedMessages: [ChatMessage]
        /// Number of messages that were dropped during sanitization.
        let droppedCount: Int
        /// Roles of dropped messages (for debug logging).
        let droppedRoles: [String]
        /// Whether any sanitization was performed.
        var wasModified: Bool { droppedCount > 0 }
    }
    
    // MARK: - Role Sequence Logging (DEBUG-safe)
    
    /// Logs the role sequence without exposing content, arguments, paths, or URLs.
    nonisolated static func logRoleSequence(
        provider: String,
        messages: [ChatMessage]
    ) {
        #if DEBUG
        let roles = messages.map { msg -> String in
            var role = msg.role.rawValue
            // Annotate tool-related messages
            if msg.role == .assistant, let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                role += "[+\(toolCalls.count)tc]"
            }
            if msg.role == .tool, let tcID = msg.toolCallID {
                // Only show first 8 chars of tool call ID for matching
                let shortID = String(tcID.prefix(8))
                role += "[→\(shortID)]"
            }
            return role
        }
        
        // Log in chunks to avoid truncation
        let chunkSize = 20
        let total = roles.count
        for (index, chunk) in roles.chunked(into: chunkSize).enumerated() {
            let start = index * chunkSize + 1
            let end = min(start + chunk.count - 1, total)
            logger.debug(
                "🔗 [\(provider, privacy: .public)] Roles [\(start)-\(end)/\(total)]: \(chunk.joined(separator: " → "), privacy: .public)"
            )
        }
        #endif
    }
    
    // MARK: - Sanitization
    
    /// Sanitizes the message sequence by removing invalid messages.
    /// This is a FAIL-OPEN operation: invalid segments are dropped, not rejected.
    ///
    /// Rules applied:
    /// 1. Remove trailing empty assistant messages (placeholders)
    /// 2. Remove orphaned tool messages (no matching prior assistant toolCall)
    /// 3. Ensure tool messages follow their parent assistant message
    nonisolated static func sanitize(
        messages: [ChatMessage],
        provider: String
    ) -> ValidationResult {
        var sanitized: [ChatMessage] = []
        var droppedRoles: [String] = []
        
        // Build a set of valid tool call IDs from assistant messages (in order)
        // This maps toolCallID -> index of the assistant message that requested it
        var toolCallOrigins: [String: Int] = [:]
        
        for (index, msg) in messages.enumerated() {
            if msg.role == .assistant, let toolCalls = msg.toolCalls {
                for tc in toolCalls {
                    toolCallOrigins[tc.id] = index
                }
            }
        }
        
        // Track which tool calls have been answered
        var answeredToolCalls: Set<String> = []
        
        // Process messages
        for (index, msg) in messages.enumerated() {
            switch msg.role {
            case .system, .user:
                // System and user messages always pass through
                sanitized.append(msg)
                
            case .assistant:
                // Check for trailing empty placeholder
                let isTrailing = index == messages.count - 1
                let isEmpty = msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let hasToolCalls = !(msg.toolCalls?.isEmpty ?? true)
                
                if isTrailing && isEmpty && !hasToolCalls {
                    // Drop trailing empty assistant placeholder
                    droppedRoles.append("assistant[empty-trailing]")
                    logger.debug(
                        "⚠️ [\(provider, privacy: .public)] Dropped trailing empty assistant message"
                    )
                } else {
                    sanitized.append(msg)
                }
                
            case .tool:
                guard let toolCallID = msg.toolCallID else {
                    // Tool message without toolCallID - orphaned
                    droppedRoles.append("tool[no-id]")
                    logger.warning(
                        "⚠️ [\(provider, privacy: .public)] Dropped tool message without toolCallID"
                    )
                    continue
                }
                
                guard let originIndex = toolCallOrigins[toolCallID] else {
                    // No matching assistant message requested this tool
                    droppedRoles.append("tool[orphan:\(String(toolCallID.prefix(8)))]")
                    logger.warning(
                        "⚠️ [\(provider, privacy: .public)] Dropped orphaned tool message (no matching toolCall)"
                    )
                    continue
                }
                
                // Ensure the tool message comes AFTER its origin assistant message in sanitized output
                // Find the position of the origin assistant in sanitized array
                let originInSanitized = sanitized.lastIndex { sanitizedMsg in
                    if sanitizedMsg.role == .assistant, let tcs = sanitizedMsg.toolCalls {
                        return tcs.contains { $0.id == toolCallID }
                    }
                    return false
                }
                
                if originInSanitized == nil {
                    // The origin assistant was dropped - this tool result is now orphaned
                    droppedRoles.append("tool[origin-dropped:\(String(toolCallID.prefix(8)))]")
                    logger.warning(
                        "⚠️ [\(provider, privacy: .public)] Dropped tool message (origin assistant was removed)"
                    )
                    continue
                }
                
                // Check for duplicate tool responses
                if answeredToolCalls.contains(toolCallID) {
                    droppedRoles.append("tool[duplicate:\(String(toolCallID.prefix(8)))]")
                    logger.warning(
                        "⚠️ [\(provider, privacy: .public)] Dropped duplicate tool response"
                    )
                    continue
                }
                
                answeredToolCalls.insert(toolCallID)
                sanitized.append(msg)
            }
        }
        
        let droppedCount = messages.count - sanitized.count
        
        if droppedCount > 0 {
            logger.info(
                "🔧 [\(provider, privacy: .public)] Sanitized message sequence: dropped \(droppedCount) message(s)"
            )
        }
        
        return ValidationResult(
            sanitizedMessages: sanitized,
            droppedCount: droppedCount,
            droppedRoles: droppedRoles
        )
    }
}

// MARK: - Array Chunking Helper

extension Array {
    /// Splits the array into chunks of the specified size.
    fileprivate func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
