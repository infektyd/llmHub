//
//  ArtifactService.swift
//  llmHub
//
//  Created by User on 2026-01-02.
//

import Foundation

/// Service responsible for detecting, extracting, and managing artifacts
/// from message content and user input.
enum ArtifactService {

    /// Result of parsing message content
    struct DetectionResult {
        let cleanContent: String
        let artifacts: [ArtifactPayload]
    }

    /// Detects artifacts within a message string based on heuristics.
    /// Extracts large code blocks and JSON blobs into artifacts, removing them from the main text.
    ///
    /// - Parameters:
    ///   - content: The raw message content from an LLM.
    ///   - messageID: The ID of the message (for stable artifact IDs).
    /// - Returns: A tuple containing the cleaned text and a list of artifacts.
    static func detect(from content: String, messageID: UUID) -> DetectionResult {
        var artifacts: [ArtifactPayload] = []
        var cleanContent = content

        // 1. Extract Code Blocks (```lang ... ```)
        // We look for blocks that are "significant" enough to be artifacts.
        // Heuristic: > 5 lines OR > 200 characters
        let codeBlockPattern = /```(\w+)?\n([\s\S]*?)```/

        let matches = content.matches(of: codeBlockPattern)
        // Process in reverse order to maintain indices while replacing
        matches.reversed().forEach { match in
            _ = content[match.range]
            let language = String(match.output.1 ?? "text")
            let codeContent = String(match.output.2)

            if isSignificant(codeContent) {
                // Create artifact
                let artifactID = Canvas2StableIDs.artifactID(
                    messageID: messageID,
                    metadata: ArtifactMetadata(
                        filename: "Snippet.\(language)",  // accurate naming would require smarter parsing
                        content: codeContent,
                        language: mapLanguage(language),
                        sizeBytes: codeContent.utf8.count
                    )
                )

                let payload = ArtifactPayload(
                    id: artifactID,
                    title: "Code Snippet (\(language))",
                    kind: .code,
                    status: .success,
                    previewText: codeContent,
                    actions: [.copy, .open],
                    metadata: nil  // We don't have full metadata here, just payload
                )

                artifacts.append(payload)

                // Remove from main content, replace with a marker or nothing?
                // For now, we remove it to keep transcript clean.
                // We might want to leave a small reference.
                cleanContent.replaceSubrange(match.range, with: "")
            }
        }

        // 2. HTTP Responses (Naive detection for now)
        // Look for typical HTTP headers if they appear at start of line
        // content-type: application/json

        // Cleanup extra newlines created by removal
        cleanContent = cleanContent.replacingOccurrences(of: "\n\n\n", with: "\n\n")

        return DetectionResult(
            cleanContent: cleanContent.trimmingCharacters(in: .whitespacesAndNewlines),
            artifacts: artifacts.reversed())
    }

    /// Determines if a code block is large enough to be extracted as an artifact.
    private static func isSignificant(_ content: String) -> Bool {
        let lineCount = content.components(separatedBy: .newlines).count
        let charCount = content.count
        return lineCount > 5 || charCount > 200
    }

    private static func mapLanguage(_ raw: String) -> CodeLanguage {
        switch raw.lowercased() {
        case "swift": return .swift
        case "python", "py": return .python
        case "json": return .json
        case "js", "javascript": return .javascript
        case "md", "markdown": return .markdown
        default: return .text
        }
    }
}
