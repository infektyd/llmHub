//
//  PasteConversionEngine.swift
//  llmHub
//
//  Pure Swift engine for deciding whether pasted text should be inline or attached.
//  No AppKit/UIKit imports - cross-platform by design.
//

import Foundation

// MARK: - PasteConversionResult

/// Result of evaluating pasted text for conversion to attachment.
struct PasteConversionResult: Sendable {
    /// Action to take with the pasted content.
    enum Action: Sendable {
        case inline  // Keep text in composer
        case attach  // Convert to artifact attachment
    }

    let action: Action
    let suggestedFilename: String
    let detectedExtension: String
    let charCount: Int
    let lineCount: Int
    let artifactID: UUID

    /// Short ID for stub display (first 6 chars of UUID).
    var shortID: String {
        String(artifactID.uuidString.prefix(6))
    }
}

// MARK: - PasteConversionEngine

/// Engine for evaluating large pastes and deciding inline vs. attachment.
///
/// Design: Pure Swift with no platform dependencies. Uses fast heuristics
/// for file type detection without deep parsing.
enum PasteConversionEngine {

    // MARK: - Default Thresholds

    /// Character count threshold for conversion.
    static let defaultCharThreshold = 4000

    /// Line count threshold for conversion.
    static let defaultLineThreshold = 120

    /// Minimum character delta to consider as paste (vs. typing/autocomplete).
    static let defaultPasteDeltaThreshold = 800

    /// Minimum line delta to consider as paste.
    static let defaultLineDeltaThreshold = 40

    // MARK: - Evaluation

    /// Evaluates text to determine if it should be converted to an attachment.
    ///
    /// - Parameters:
    ///   - text: The full text content to evaluate.
    ///   - charThreshold: Character count above which to attach (default: 4000).
    ///   - lineThreshold: Line count above which to attach (default: 120).
    ///   - forceInline: If true, always returns `.inline` regardless of size.
    /// - Returns: A `PasteConversionResult` with the recommended action.
    static func evaluate(
        text: String,
        charThreshold: Int = defaultCharThreshold,
        lineThreshold: Int = defaultLineThreshold,
        forceInline: Bool = false
    ) -> PasteConversionResult {
        let charCount = text.count
        let lineCount = text.components(separatedBy: .newlines).count
        let ext = detectExtension(from: text)
        let artifactID = UUID()
        let filename = generateFilename(extension: ext)

        // Force inline bypasses all checks
        if forceInline {
            return PasteConversionResult(
                action: .inline,
                suggestedFilename: filename,
                detectedExtension: ext,
                charCount: charCount,
                lineCount: lineCount,
                artifactID: artifactID
            )
        }

        // Attach if exceeds either threshold
        let shouldAttach = charCount >= charThreshold || lineCount >= lineThreshold

        return PasteConversionResult(
            action: shouldAttach ? .attach : .inline,
            suggestedFilename: filename,
            detectedExtension: ext,
            charCount: charCount,
            lineCount: lineCount,
            artifactID: artifactID
        )
    }

    /// Quick check if a delta looks like a paste event (vs. typing/autocomplete).
    ///
    /// - Parameters:
    ///   - deltaChars: Number of characters added in single edit.
    ///   - deltaLines: Number of lines added in single edit.
    ///   - pasteDeltaThreshold: Char threshold for paste detection (default: 800).
    ///   - lineDeltaThreshold: Line threshold for paste detection (default: 40).
    /// - Returns: True if delta looks like a paste event.
    static func looksLikePaste(
        deltaChars: Int,
        deltaLines: Int,
        pasteDeltaThreshold: Int = defaultPasteDeltaThreshold,
        lineDeltaThreshold: Int = defaultLineDeltaThreshold
    ) -> Bool {
        deltaChars >= pasteDeltaThreshold || deltaLines >= lineDeltaThreshold
    }

    // MARK: - Extension Detection

    /// Detects file extension from content using fast heuristics.
    /// Priority: JSON → Markdown → CSV → TXT
    static func detectExtension(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // JSON: Starts with { or [
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            // Validate it looks like JSON (has matching brackets)
            if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
                || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
            {
                return "json"
            }
        }

        // Markdown: Has markdown-specific patterns
        if containsMarkdownPatterns(content) {
            return "md"
        }

        // CSV: Has consistent comma-separated structure
        if looksLikeCSV(content) {
            return "csv"
        }

        // Default: Plain text
        return "txt"
    }

    // MARK: - Filename Generation

    /// Generates a timestamped filename for the paste.
    static func generateFilename(extension ext: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: Date())
        return "paste_\(timestamp).\(ext)"
    }

    // MARK: - Private Helpers

    private static func containsMarkdownPatterns(_ content: String) -> Bool {
        // Check for common markdown indicators
        let patterns = [
            "```",  // Code blocks
            "# ",  // Headers
            "## ",
            "### ",
            "- [ ]",  // Task lists
            "- [x]",
            "**",  // Bold
            "| ",  // Tables
            "[!",  // GitHub alerts
        ]

        for pattern in patterns {
            if content.contains(pattern) {
                return true
            }
        }

        // Check for link syntax
        let linkPattern = "\\[.+\\]\\(.+\\)"
        if content.range(of: linkPattern, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    private static func looksLikeCSV(_ content: String) -> Bool {
        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard lines.count >= 3 else { return false }

        // Check first few lines have consistent comma count
        let commaCounts = lines.prefix(5).map { line in
            line.filter { $0 == "," }.count
        }

        guard let firstCount = commaCounts.first, firstCount >= 2 else {
            return false
        }

        // All checked lines should have similar comma count
        return commaCounts.allSatisfy { abs($0 - firstCount) <= 1 }
    }
}
