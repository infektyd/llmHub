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

    // Work in lowercase, then apply casing rules at the end.
    var name = trimmed.lowercased()

    // 1. Strip date suffixes: -YYYYMMDD or -YYYY-MM-DD (also accept underscores)
    name = name.replacingOccurrences(of: #"-\d{4}-\d{2}-\d{2}$"#, with: "", options: .regularExpression)
    name = name.replacingOccurrences(of: #"_\d{4}_\d{2}_\d{2}$"#, with: "", options: .regularExpression)
    name = name.replacingOccurrences(of: #"-\d{8}$"#, with: "", options: .regularExpression)
    name = name.replacingOccurrences(of: #"_\d{8}$"#, with: "", options: .regularExpression)

    // 2. Normalize separators to hyphens
    name = name.replacingOccurrences(of: #"[\s_]+"#, with: "-", options: .regularExpression)

    // 3. Strip noise suffix tokens (order matters: compound phrases first)
    // We strip as tokens to avoid accidental substring mangling.
    let noiseTokens: Set<String> = [
        "fast-reasoning",
        "fast",
        "reasoning",
        "preview",
        "latest",
        "experimental",
        "turbo"
    ]

    // 4. Tokenize by hyphen
    var tokens = name
        .split(separator: "-", omittingEmptySubsequences: true)
        .map { String($0) }

    guard !tokens.isEmpty else { return raw }

    // Drop compound noise tokens like "fast-reasoning" if present in the raw string.
    // (This handles ids like grok-4.1-fast-reasoning cleanly.)
    if name.contains("-fast-reasoning") {
        tokens.removeAll { $0 == "fast" || $0 == "reasoning" }
    }

    // Drop remaining noise tokens.
    tokens.removeAll { noiseTokens.contains($0) }
    guard !tokens.isEmpty else { return raw }

    // 5. Normalize version patterns across tokens:
    // - Join adjacent digit-only tokens into dotted versions: ["4","1"] -> "4.1"
    // - Keep tokens containing letters intact (e.g. "4o").
    var normalized: [String] = []
    var i = 0
    while i < tokens.count {
        let current = tokens[i]
        let next = (i + 1 < tokens.count) ? tokens[i + 1] : nil

        let currentDigitsOnly = !current.isEmpty && current.allSatisfy { $0.isNumber }
        let nextDigitsOnly = next.map { !$0.isEmpty && $0.allSatisfy { $0.isNumber } } ?? false

        if currentDigitsOnly, nextDigitsOnly {
            normalized.append("\(current).\(next!)")
            i += 2
            continue
        }

        // Normalize digit-digit inside a token: "4-1" would be split already, but handle oddities.
        let embedded = current.replacingOccurrences(
            of: #"(\d)-(\d)"#,
            with: "$1.$2",
            options: .regularExpression
        )
        normalized.append(embedded)
        i += 1
    }

    tokens = normalized

    // 6. Format tokens (title-case + special handling)
    func prettyToken(_ token: String) -> String {
        let lower = token.lowercased()
        switch lower {
        case "gpt": return "GPT"
        case "grok": return "Grok"
        case "claude": return "Claude"
        case "gemini": return "Gemini"
        case "mistral": return "Mistral"
        case "llama": return "LLaMA"
        default:
            // Preserve version-like tokens such as 4o, 2.0, 3.5
            if lower.range(of: #"^\d+(?:\.\d+)*[a-z]?$"#, options: .regularExpression) != nil {
                return lower
            }
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }
    }

    // Special format for GPT to keep GPT-4o style.
    if tokens.first?.lowercased() == "gpt" {
        if tokens.count >= 2 {
            var out: [String] = ["GPT-\(prettyToken(tokens[1]))"]
            if tokens.count > 2 {
                out.append(contentsOf: tokens.dropFirst(2).map(prettyToken))
            }
            return out.joined(separator: " ")
        }
        return "GPT"
    }

    return tokens.map(prettyToken).joined(separator: " ").trimmingCharacters(in: .whitespaces)
}
