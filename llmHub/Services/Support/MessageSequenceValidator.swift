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

    nonisolated private static let logger = Logger(
        subsystem: "com.llmhub", category: "MessageSequence")

    // MARK: - Validation Result

    struct ValidationResult: Sendable {
        /// The sanitized messages ready for API submission.
        let sanitizedMessages: [ChatMessage]

        // MARK: Mutation Summary
        /// Whether any sanitization was performed.
        let didMutate: Bool
        /// Total number of messages that were dropped during sanitization.
        let droppedMessageCount: Int

        // MARK: Dropped Messages by Role
        /// Number of user messages dropped.
        let droppedUserCount: Int
        /// Number of assistant messages dropped.
        let droppedAssistantCount: Int
        /// Number of tool messages dropped.
        let droppedToolCount: Int
        /// Number of system messages dropped.
        let droppedSystemCount: Int

        // MARK: Dropped Messages by Reason
        /// Messages dropped with reason counters (e.g., "orphanTool": 2, "duplicateTool": 1).
        let droppedByReason: [String: Int]

        // MARK: Role Sequences (for debugging and observability)
        /// Role sequence before sanitization (roles only, no content).
        let preRoleSequence: [String]
        /// Role sequence after sanitization (roles only, no content).
        let postRoleSequence: [String]

        // MARK: Legacy Compatibility
        /// Roles of dropped messages (for debug logging) - kept for backward compatibility.
        var droppedRoles: [String] {
            Array(
                droppedByReason.flatMap { reason, count in
                    (0..<count).map { _ in reason }
                })
        }
        /// Legacy alias for droppedMessageCount.
        var droppedCount: Int { droppedMessageCount }
        /// Legacy alias for didMutate.
        var wasModified: Bool { didMutate }
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
    /// 4. Deduplicate tool responses (same toolCallID)
    nonisolated static func sanitize(
        messages: [ChatMessage],
        provider: String
    ) -> ValidationResult {
        // MARK: - Capture Pre-Sanitization State
        let preRoleSequence = messages.map { msg -> String in
            var role = msg.role.rawValue
            if msg.role == .assistant, let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                role += "[+\(toolCalls.count)tc]"
            }
            if msg.role == .tool, let tcID = msg.toolCallID {
                role += "[→\(String(tcID.prefix(8)))]"
            }
            return role
        }

        var sanitized: [ChatMessage] = []
        var droppedByReason: [String: Int] = [:]
        var droppedByRole: [MessageRole: Int] = [:]

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
                    droppedByReason["trailingEmptyAssistant", default: 0] += 1
                    droppedByRole[.assistant, default: 0] += 1
                    logger.debug(
                        "⚠️ [\(provider, privacy: .public)] Dropped trailing empty assistant message"
                    )
                } else {
                    sanitized.append(msg)
                }

            case .tool:
                guard let toolCallID = msg.toolCallID else {
                    // Tool message without toolCallID - orphaned
                    droppedByReason["toolMissingID", default: 0] += 1
                    droppedByRole[.tool, default: 0] += 1
                    logger.warning(
                        "⚠️ [\(provider, privacy: .public)] Dropped tool message without toolCallID"
                    )
                    continue
                }

                guard toolCallOrigins[toolCallID] != nil else {
                    // No matching assistant message requested this tool
                    droppedByReason["orphanTool", default: 0] += 1
                    droppedByRole[.tool, default: 0] += 1
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
                    droppedByReason["toolOriginDropped", default: 0] += 1
                    droppedByRole[.tool, default: 0] += 1
                    logger.warning(
                        "⚠️ [\(provider, privacy: .public)] Dropped tool message (origin assistant was removed)"
                    )
                    continue
                }

                // Check for duplicate tool responses
                if answeredToolCalls.contains(toolCallID) {
                    droppedByReason["duplicateTool", default: 0] += 1
                    droppedByRole[.tool, default: 0] += 1
                    logger.warning(
                        "⚠️ [\(provider, privacy: .public)] Dropped duplicate tool response"
                    )
                    continue
                }

                answeredToolCalls.insert(toolCallID)
                sanitized.append(msg)
            }
        }

        // MARK: - Capture Post-Sanitization State
        let postRoleSequence = sanitized.map { msg -> String in
            var role = msg.role.rawValue
            if msg.role == .assistant, let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                role += "[+\(toolCalls.count)tc]"
            }
            if msg.role == .tool, let tcID = msg.toolCallID {
                role += "[→\(String(tcID.prefix(8)))]"
            }
            return role
        }

        let droppedMessageCount = messages.count - sanitized.count
        let didMutate = droppedMessageCount > 0

        if didMutate {
            logger.info(
                "🔧 [\(provider, privacy: .public)] Sanitized message sequence: dropped \(droppedMessageCount) message(s)"
            )
        }

        return ValidationResult(
            sanitizedMessages: sanitized,
            didMutate: didMutate,
            droppedMessageCount: droppedMessageCount,
            droppedUserCount: droppedByRole[.user, default: 0],
            droppedAssistantCount: droppedByRole[.assistant, default: 0],
            droppedToolCount: droppedByRole[.tool, default: 0],
            droppedSystemCount: droppedByRole[.system, default: 0],
            droppedByReason: droppedByReason,
            preRoleSequence: preRoleSequence,
            postRoleSequence: postRoleSequence
        )
    }
}

// MARK: - Array Chunking Helper

extension Array {
    /// Splits the array into chunks of the specified size.
    nonisolated fileprivate func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
