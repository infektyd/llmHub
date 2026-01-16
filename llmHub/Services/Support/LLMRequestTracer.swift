//
//  LLMRequestTracer.swift
//  llmHub
//
//  Centralized request tracing for all LLM providers.
//  Uses OSLog with proper levels so logs are filterable in Console.app.
//
//  To view in Console.app:
//    1. Filter by subsystem: "com.llmhub"
//    2. Filter by category: "LLMRequest"
//    3. Enable "Include Info Messages" and "Include Debug Messages" in Action menu
//

import Foundation
import OSLog

/// Logger for LLM tracing - Sendable and thread-safe
struct LLMTrace {
    nonisolated private static let logger = Logger(
        subsystem: "com.llmhub", category: "LLMRequest")
    private init() {}  // Prevent instantiation

    // MARK: - Request Lifecycle

    /// Log when a request starts being built
    nonisolated static func requestStarted(
        provider: String, model: String, messageCount: Int, toolCount: Int
    ) {
        logger.info(
            "➡️ [\(provider)] Request started - model: \(model), messages: \(messageCount), tools: \(toolCount)"
        )
    }

    /// Log request details (debug level - hidden by default)
    nonisolated static func requestDetails(provider: String, url: String, bodyPreview: String) {
        let safeURL = redactURL(url)
        let safeBody = redactBody(bodyPreview)
        logger.debug("📋 [\(provider)] URL: \(safeURL)")
        logger.debug("📋 [\(provider)] Body: \(safeBody.prefix(300))...")
    }

    /// Log when request is sent to the network
    nonisolated static func requestSent(provider: String) {
        logger.debug("📤 [\(provider)] Request sent to network")
    }

    // MARK: - Response Lifecycle

    /// Log when response headers are received
    nonisolated static func responseReceived(provider: String, statusCode: Int) {
        if (200...299).contains(statusCode) {
            logger.info("✅ [\(provider)] HTTP \(statusCode)")
        } else {
            logger.error("❌ [\(provider)] HTTP \(statusCode)")
        }
    }

    /// Log streaming progress (debug level)
    nonisolated static func streamChunk(provider: String, chunkNumber: Int, deltaLength: Int) {
        if chunkNumber <= 3 || chunkNumber % 10 == 0 {
            logger.debug("📥 [\(provider)] Chunk #\(chunkNumber), +\(deltaLength) chars")
        }
    }

    /// Log stream completion
    nonisolated static func streamComplete(provider: String, totalLength: Int, durationMs: Int) {
        logger.info("✅ [\(provider)] Complete: \(totalLength) chars in \(durationMs)ms")
    }

    // MARK: - Tool Calls

    /// Log tool call detected
    nonisolated static func toolCallDetected(provider: String, toolName: String, toolId: String) {
        logger.info("🔧 [\(provider)] Tool call: \(toolName) (id: \(toolId.prefix(12)))")
    }

    // MARK: - Request Instrumentation (DEBUG-safe, no content logged)

    /// Log request cost instrumentation metrics.
    /// All values are estimates; no message content is included.
    nonisolated static func requestInstrumentation(
        provider: String,
        messageCount: Int,
        toolCount: Int,
        manifestSizeChars: Int,
        manifestSizeTokensEstimate: Int,
        totalTokenEstimate: Int
    ) {
        logger.info(
            """
            📊 [\(provider)] Instrumentation: \
            msgs=\(messageCount), tools=\(toolCount), \
            manifest=\(manifestSizeChars)ch/~\(manifestSizeTokensEstimate)tok, \
            total=~\(totalTokenEstimate)tok
            """
        )
    }

    /// Log message sequence validation results.
    nonisolated static func sequenceValidation(
        provider: String,
        originalCount: Int,
        sanitizedCount: Int,
        droppedRoles: [String]
    ) {
        if originalCount != sanitizedCount {
            logger.warning(
                "⚠️ [\(provider)] Sequence sanitized: \(originalCount) → \(sanitizedCount) messages, dropped: \(droppedRoles.joined(separator: ", "))"
            )
        }
    }

    /// Log attachment metrics for debugging.
    /// DEBUG-safe: logs count, filenames, types, and sizes. Never logs file contents or absolute paths.
    nonisolated static func attachmentMetrics(
        provider: String,
        attachmentCount: Int,
        attachmentMeta: [(id: String, filename: String, type: String, bytes: Int)]
    ) {
        if attachmentCount > 0 {
            let summary = attachmentMeta.prefix(3).map {
                "\($0.filename)(\($0.type),\($0.bytes)B)"
            }.joined(separator: ", ")
            let more = attachmentCount > 3 ? " +\(attachmentCount - 3) more" : ""
            logger.info("📎 [\(provider)] Attachments: \(attachmentCount) - \(summary)\(more)")
        } else {
            logger.debug("📎 [\(provider)] Attachments: 0")
        }
    }

    // MARK: - Errors

    /// Log API errors
    nonisolated static func error(provider: String, message: String) {
        logger.error("❌ [\(provider)] \(message)")
    }

    /// Log error with response body
    nonisolated static func errorWithBody(provider: String, statusCode: Int, body: String) {
        logger.error("❌ [\(provider)] HTTP \(statusCode): \(body.prefix(500))")
    }

    // MARK: - Special Cases

    /// Log when a feature is skipped
    nonisolated static func featureSkipped(provider: String, feature: String, reason: String) {
        logger.info("⚠️ [\(provider)] \(feature): \(reason)")
    }

    /// Log authentication status
    nonisolated static func authStatus(provider: String, hasKey: Bool) {
        if hasKey {
            logger.debug("🔑 [\(provider)] API key found")
        } else {
            logger.error("🔑 [\(provider)] No API key!")
        }
    }

    nonisolated private static func redactURL(_ url: String) -> String {
        let pattern = #"([?&](?:key|api_key|apikey|access_token|token)=)[^&]+"#
        return url.replacingOccurrences(
            of: pattern, with: "$1[REDACTED]", options: .regularExpression)
    }

    nonisolated private static func redactBody(_ body: String) -> String {
        var sanitized = body
        let jsonPattern =
            #"("(?:key|api_key|apikey|access_token|token|authorization)"\s*:\s*")[^"]*""#
        sanitized = sanitized.replacingOccurrences(
            of: jsonPattern,
            with: #"$1[REDACTED]""#,
            options: .regularExpression
        )
        let bearerPattern = #"(?i)\bBearer\s+[A-Za-z0-9._-]+"#
        sanitized = sanitized.replacingOccurrences(
            of: bearerPattern,
            with: "Bearer [REDACTED]",
            options: .regularExpression
        )
        return sanitized
    }
}
