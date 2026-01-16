//
//  ToolRunLabelerService.swift
//  llmHub
//
//  Generates run bundle titles/rationales with AFM + Gemini fallback.
//

import Foundation
import FoundationModels

nonisolated final class ToolRunLabelerService: Sendable {
    private let keychainStore: KeychainStore

    init(keychainStore: KeychainStore) {
        self.keychainStore = keychainStore
    }

    @MainActor
    convenience init() {
        self.init(keychainStore: KeychainStore())
    }

    var isAvailable: Bool {
        if #available(macOS 15.0, iOS 18.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        return false
    }

    func label(for toolCalls: [ToolCall], expectedToolCount: Int) async -> ToolRunLabel? {
        let summary = ToolRunLabelSummary(toolCalls: toolCalls, expectedToolCount: expectedToolCount)

        if isAvailable, #available(macOS 15.0, iOS 18.0, *) {
            if let label = try? await labelWithAFM(summary: summary) {
                return label
            }
        }

        if let label = await labelWithGemini(summary: summary) {
            return label
        }

        return nil
    }

    @available(macOS 15.0, iOS 18.0, *)
    private func labelWithAFM(summary: ToolRunLabelSummary) async throws -> ToolRunLabel? {
        let model = SystemLanguageModel(useCase: .contentTagging)
        let session = LanguageModelSession(model: model)
        let prompt = buildPrompt(summary: summary)
        let response = try await session.respond(to: prompt)
        return decodeLabel(from: response.content)
    }

    private func labelWithGemini(summary: ToolRunLabelSummary) async -> ToolRunLabel? {
        guard let apiKey = await keychainStore.apiKey(for: .google), !apiKey.isEmpty else {
            return nil
        }

        guard #available(iOS 26.1, macOS 26.1, *) else {
            return nil
        }

        let prompt = buildPrompt(summary: summary)

        do {
            let manager = await MainActor.run { GeminiManager(apiKey: apiKey) }
            let response = try await manager.generateContent(
                prompt: prompt,
                model: GeminiPinnedModels.afmFallbackFlash,
                temperature: Float(GeminiPinnedModels.afmFallbackTemperature),
                responseMimeType: "application/json"
            )
            return decodeLabel(from: response.text ?? "")
        } catch {
            return nil
        }
    }

    private func buildPrompt(summary: ToolRunLabelSummary) -> String {
        let summaryJSON = summary.encodedJSON() ?? "{}"
        return """
        You generate short labels for a bundle of tool runs.
        Use ONLY the provided SUMMARY and do not infer or add private data.

        Return JSON only (no prose, no markdown, no code fences).
        Output MUST be valid JSON with keys:
        - title (string)
        - rationale (string)
        - tags (optional array of strings)

        Rules:
        - title <= 60 chars
        - rationale <= 140 chars
        - tags optional, max 5 items, each <= 20 chars
        - No paths, URLs, tokens, secrets, IDs, file contents, or user data
        - High-level phrasing only

        SUMMARY:
        \(summaryJSON)
        """
    }

    private func decodeLabel(from content: String) -> ToolRunLabel? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            jsonString = String(trimmed[start...end])
        } else {
            jsonString = trimmed
        }

        guard let data = jsonString.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(ToolRunLabel.self, from: data)
        else {
            return nil
        }

        return sanitizeLabel(decoded)
    }

    private func sanitizeLabel(_ label: ToolRunLabel) -> ToolRunLabel? {
        guard let title = sanitizeText(label.title, maxLength: 60),
            let rationale = sanitizeText(label.rationale, maxLength: 140)
        else {
            return nil
        }

        let tags = label.tags?.compactMap { sanitizeTag($0) }
        let limitedTags = tags?.prefix(5)
        let filteredTags = limitedTags?.isEmpty == true ? nil : Array(limitedTags ?? [])
        return ToolRunLabel(title: title, rationale: rationale, tags: filteredTags)
    }

    private func sanitizeText(_ text: String, maxLength: Int) -> String? {
        let collapsed = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        let clipped = String(collapsed.prefix(maxLength))
        guard !containsSensitivePatterns(clipped) else { return nil }
        return clipped
    }

    private func sanitizeTag(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let clipped = String(trimmed.prefix(20))
        guard !containsSensitivePatterns(clipped) else { return nil }
        return clipped
    }

    private func containsSensitivePatterns(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let patterns = [
            "http://",
            "https://",
            "www.",
            "file://",
            "/users/",
            "~/",
            "c:\\\\",
            "\\\\",
            "sk-",
            "api_key",
            "apikey"
        ]
        return patterns.contains { lowered.contains($0) }
    }
}

nonisolated struct ToolRunLabelSummary: Encodable {
    nonisolated struct ToolEntry: Encodable {
        let name: String
        let category: String
        let count: Int
    }

    let totalTools: Int
    let expectedToolCount: Int
    let tools: [ToolEntry]
    let categories: [String: Int]

    init(toolCalls: [ToolCall], expectedToolCount: Int) {
        totalTools = toolCalls.count
        self.expectedToolCount = expectedToolCount

        var counts: [String: Int] = [:]
        for call in toolCalls {
            counts[call.name, default: 0] += 1
        }

        let sortedNames = counts.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        tools = sortedNames.map { name in
            let category = ToolRunLabelCategory.category(for: name).rawValue
            return ToolEntry(name: name, category: category, count: counts[name] ?? 0)
        }

        var categoryCounts: [String: Int] = [:]
        for name in sortedNames {
            let category = ToolRunLabelCategory.category(for: name).rawValue
            categoryCounts[category, default: 0] += counts[name] ?? 0
        }
        categories = categoryCounts
    }

    func encodedJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

nonisolated enum ToolRunLabelCategory: String {
    case readingFiles = "reading_files"
    case searching = "searching"
    case browsingFiles = "browsing_files"
    case fetchingWeb = "fetching_web"
    case editingFiles = "editing_files"
    case runningCommands = "running_commands"
    case computing = "computing"
    case previewingUI = "previewing_ui"
    case readingResources = "reading_resources"
    case savingContext = "saving_context"
    case other = "other"

    static func category(for toolName: String) -> ToolRunLabelCategory {
        switch toolName.lowercased() {
        case "read_file", "read_notebook":
            return .readingFiles
        case "list_dir", "find_by_name":
            return .browsingFiles
        case "grep_search", "search_web":
            return .searching
        case "read_url_content", "http_request":
            return .fetchingWeb
        case "apply_patch", "write_to_file", "edit_notebook":
            return .editingFiles
        case "run_command", "shell":
            return .runningCommands
        case "browser_preview":
            return .previewingUI
        case "code_interpreter", "calculator":
            return .computing
        case "list_resources", "read_resource":
            return .readingResources
        case "create_memory":
            return .savingContext
        default:
            return .other
        }
    }
}
