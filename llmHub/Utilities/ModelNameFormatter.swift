//
//  ModelNameFormatter.swift
//  llmHub
//
//  Small utility for turning raw model IDs into human-friendly labels.
//

import Foundation

func cleanModelName(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return raw }

    var working = trimmed

    // 1) Strip explicit date suffixes
    // - "-20250514" / "-2024-11-20" (also accept underscores/spaces as separators)
    working = working.replacingOccurrences(of: #"[-_ ]\d{8}$"#, with: "", options: .regularExpression)
    working = working.replacingOccurrences(of: #"[-_ ]\d{4}[-_]\d{2}[-_]\d{2}$"#, with: "", options: .regularExpression)

    // 2) Normalize separators: treat whitespace/underscores as hyphens.
    working = working.replacingOccurrences(of: #"[\s_]+"#, with: "-", options: .regularExpression)

    // 3) Strip noise words (case-insensitive) wherever they appear.
    let stripWords: Set<String> = ["fast", "reasoning", "preview", "latest", "experimental", "turbo"]

    // 4) Tokenize by hyphen, then normalize versions like "4-1" -> "4.1" via token stitching.
    var tokens = working
        .split(separator: "-", omittingEmptySubsequences: true)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard !tokens.isEmpty else { return raw }

    // Drop noise tokens.
    tokens = tokens.filter { !stripWords.contains($0.lowercased()) }
    guard !tokens.isEmpty else { return raw }

    // Join adjacent purely-numeric tokens into dotted versions: "4" "1" -> "4.1".
    // Do not alter tokens containing letters (e.g., "4o").
    var normalizedTokens: [String] = []
    var index = 0
    while index < tokens.count {
        let current = tokens[index]
        let next = (index + 1 < tokens.count) ? tokens[index + 1] : nil

        let currentIsDigitsOnly = !current.isEmpty && current.allSatisfy { $0.isNumber }
        let nextIsDigitsOnly = next.map { !$0.isEmpty && $0.allSatisfy { $0.isNumber } } ?? false

        if currentIsDigitsOnly, nextIsDigitsOnly {
            normalizedTokens.append("\(current).\(next!)")
            index += 2
        } else {
            // Also normalize embedded digit-digit patterns inside a token (rare): "4-1" already split,
            // but handle accidental "4-1" remnants or spaced "4 1" that became "4-1" earlier.
            normalizedTokens.append(current)
            index += 1
        }
    }

    tokens = normalizedTokens

    // 5) Capitalize and format.
    let keepTitleCase: Set<String> = [
        "pro", "flash", "sonnet", "opus", "haiku", "mini", "large", "medium", "small"
    ]

    func titleToken(_ token: String) -> String {
        guard !token.isEmpty else { return token }

        let lower = token.lowercased()

        switch lower {
        case "gpt": return "GPT"
        case "grok": return "Grok"
        case "claude": return "Claude"
        case "gemini": return "Gemini"
        case "mistral": return "Mistral"
        default:
            if keepTitleCase.contains(lower) {
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }

            // Preserve numeric/version tokens like "4o" or "2.0".
            let isLikelyVersion = token.range(of: #"^\d+(?:\.\d+)*[a-z]?$"#, options: .regularExpression) != nil
            if isLikelyVersion { return lower }

            // Preserve existing all-caps acronyms.
            if token.uppercased() == token { return token }

            return lower.prefix(1).uppercased() + lower.dropFirst()
        }
    }

    let brand = tokens[0].lowercased()

    // GPT: format as "GPT-4o" plus optional descriptors.
    if brand == "gpt" {
        if tokens.count >= 2 {
            var output: [String] = ["GPT-\(titleToken(tokens[1]))"]
            if tokens.count > 2 {
                output.append(contentsOf: tokens.dropFirst(2).map(titleToken))
            }
            return output.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }
        return "GPT"
    }

    // Claude: allow "claude-3-5-sonnet" -> "Claude 3.5 Sonnet" and "claude-sonnet-4" -> "Claude Sonnet 4".
    // The generic token pipeline already normalized numeric pairs, so just title-case.
    return tokens.map(titleToken).joined(separator: " ").trimmingCharacters(in: .whitespaces)
}
