//
//  Canvas2Models.swift
//  llmHub
//
//  View models and data structures for the Canvas2 UI
//

import CryptoKit
import Foundation
import SwiftUI

// MARK: - View Models

enum ToolRunBundleStatus: String, Equatable {
    case running
    case success
    case partialFailure
    case failure
}

struct ToolRunBundleViewModel: Identifiable, Equatable {
    let id: String
    let parentAssistantMessageID: UUID
    let title: String
    let toolRows: [TranscriptRowViewModel]
    let expectedToolCount: Int
    let status: ToolRunBundleStatus

    var toolCount: Int { toolRows.count }

    var displayTitle: String {
        Self.makeTitle(toolNameCounts: toolNameCounts, expectedToolCount: expectedToolCount)
    }

    var displayRationale: String {
        Self.makeRationale(toolNameCounts: toolNameCounts)
    }

    private var toolNameCounts: [String: Int] {
        toolRows.compactMap { $0.toolResultMeta?.toolName }
            .reduce(into: [:]) { partialResult, toolName in
                partialResult[toolName, default: 0] += 1
            }
    }

    // Example outputs (deterministic, tool-name only):
    // 1) tools: ["read_file", "read_file", "read_file"]
    //    title: "Running tools: read_file (3)"
    //    rationale: "Reading files to locate relevant sections."
    // 2) tools: ["read_file", "grep_search", "search_web"]
    //    title: "Running tools: read_file, grep_search, search_web"
    //    rationale: "Reading files + searching to locate relevant sections."
    // 3) tools: ["apply_patch", "read_file"] (expected: 4)
    //    title: "Running tools: apply_patch, read_file (+2)"
    //    rationale: "Reading files + editing files to gather context and apply updates."

    private static func makeTitle(
        toolNameCounts: [String: Int],
        expectedToolCount: Int,
        maxLength: Int = 60
    ) -> String {
        let fallback = "Running tools"
        guard !toolNameCounts.isEmpty else { return fallback }

        let sortedNames = toolNameCounts.keys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        let totalKnownCount = toolNameCounts.values.reduce(0, +)
        let totalExpected = max(expectedToolCount, totalKnownCount)

        var title = "\(fallback): "
        var includedCount = 0
        var usedNames = 0

        for name in sortedNames {
            guard let count = toolNameCounts[name] else { continue }
            let label = count > 1 ? "\(name) (\(count))" : name
            let candidate = usedNames == 0 ? label : ", \(label)"
            if title.count + candidate.count <= maxLength {
                title += candidate
                includedCount += count
                usedNames += 1
            } else {
                break
            }
        }

        let remainingCount = max(totalExpected - includedCount, 0)
        if remainingCount > 0 {
            let suffix = " (+\(remainingCount))"
            if title.count + suffix.count <= maxLength {
                title += suffix
            }
        }

        return title.count <= maxLength ? title : fallback
    }

    private static func makeRationale(toolNameCounts: [String: Int], maxLength: Int = 140) -> String {
        let toolNames = Array(toolNameCounts.keys)
        let categories = orderedCategories(from: toolNames)
        guard !categories.isEmpty else {
            return "Executing tools to gather results."
        }

        let needsContext = categories.contains { $0.isContextGathering }
        let needsEditing = categories.contains { $0 == .editingFiles }
        let needsVerification = categories.contains { $0.isVerification }
        let needsPreview = categories.contains { $0 == .previewingUI }
        let needsMemory = categories.contains { $0 == .savingContext }

        let purpose: String
        switch (needsContext, needsEditing, needsVerification, needsPreview, needsMemory) {
        case (true, true, _, _, _):
            purpose = "to gather context and apply updates."
        case (_, true, _, _, _):
            purpose = "to apply updates."
        case (true, _, _, _, _):
            purpose = "to locate relevant sections."
        case (_, _, true, _, _):
            purpose = "to verify results."
        case (_, _, _, true, _):
            purpose = "to validate UI."
        case (_, _, _, _, true):
            purpose = "to preserve context."
        default:
            purpose = "to support the request."
        }

        let maxSummaryLength = maxLength - purpose.count - 1
        let summary = summarizedCategories(categories, maxLength: maxSummaryLength)
        let rationale = "\(summary) \(purpose)"
        if rationale.count <= maxLength {
            return rationale
        }
        return "Executing tools to gather results."
    }

    private static func summarizedCategories(
        _ categories: [ToolCategory],
        maxLength: Int
    ) -> String {
        var summary = ""
        for category in categories {
            let part = category.summary
            let candidate = summary.isEmpty ? part : "\(summary) + \(part)"
            if candidate.count <= maxLength {
                summary = candidate
            } else {
                break
            }
        }
        return summary.isEmpty ? "Multiple tool types" : summary
    }

    private static func orderedCategories(from toolNames: [String]) -> [ToolCategory] {
        var unique: [ToolCategory: Bool] = [:]
        for name in toolNames {
            if let category = category(for: name) {
                unique[category] = true
            }
        }
        return unique.keys.sorted { $0.sortOrder < $1.sortOrder }
    }

    private static func category(for toolName: String) -> ToolCategory? {
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
            return nil
        }
    }

    private enum ToolCategory: Int {
        case readingFiles
        case searching
        case browsingFiles
        case fetchingWeb
        case editingFiles
        case runningCommands
        case computing
        case previewingUI
        case readingResources
        case savingContext

        var summary: String {
            switch self {
            case .readingFiles: return "Reading files"
            case .searching: return "Searching"
            case .browsingFiles: return "Browsing files"
            case .fetchingWeb: return "Fetching web info"
            case .editingFiles: return "Editing files"
            case .runningCommands: return "Running commands"
            case .computing: return "Computing"
            case .previewingUI: return "Previewing UI"
            case .readingResources: return "Reading resources"
            case .savingContext: return "Saving context"
            }
        }

        var sortOrder: Int { rawValue }

        var isContextGathering: Bool {
            switch self {
            case .readingFiles, .browsingFiles, .searching, .fetchingWeb, .readingResources:
                return true
            case .editingFiles, .runningCommands, .computing, .previewingUI, .savingContext:
                return false
            }
        }

        var isVerification: Bool {
            switch self {
            case .runningCommands, .computing:
                return true
            default:
                return false
            }
        }
    }
}

enum TranscriptRowKind: Equatable {
    case message
    case toolRunBundle(ToolRunBundleViewModel)
}

struct TranscriptRowViewModel: Identifiable, Equatable {
    let id: String
    let kind: TranscriptRowKind
    let role: MessageRole
    let headerLabel: String  // e.g. "Claude 3.5 Sonnet", "You"
    let headerMetaText: String?
    let content: String  // Markdown body
    let isStreaming: Bool
    let generationID: UUID?
    let artifacts: [ArtifactPayload]
    let toolCallID: String?
    let toolResultMeta: ToolResultMeta?
    let toolCallArguments: String?

    init(
        id: String,
        kind: TranscriptRowKind = .message,
        role: MessageRole,
        headerLabel: String,
        headerMetaText: String?,
        content: String,
        isStreaming: Bool,
        generationID: UUID?,
        artifacts: [ArtifactPayload],
        toolCallID: String? = nil,
        toolResultMeta: ToolResultMeta? = nil,
        toolCallArguments: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.role = role
        self.headerLabel = headerLabel
        self.headerMetaText = headerMetaText
        self.content = content
        self.isStreaming = isStreaming
        self.generationID = generationID
        self.artifacts = artifacts
        self.toolCallID = toolCallID
        self.toolResultMeta = toolResultMeta
        self.toolCallArguments = toolCallArguments
    }

    // Equatable conformance for efficient SwiftUI diffing
    static func == (lhs: TranscriptRowViewModel, rhs: TranscriptRowViewModel) -> Bool {
        return lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.role == rhs.role
            && lhs.headerLabel == rhs.headerLabel
            && lhs.headerMetaText == rhs.headerMetaText
            && lhs.content == rhs.content && lhs.isStreaming == rhs.isStreaming
            && lhs.generationID == rhs.generationID
            && lhs.artifacts == rhs.artifacts
            && lhs.toolCallID == rhs.toolCallID
            && lhs.toolResultMeta == rhs.toolResultMeta
            && lhs.toolCallArguments == rhs.toolCallArguments
    }
}

struct CanvasConversationSummary: Identifiable, Equatable {
    let id: UUID
    let displayTitle: String
    let updatedAt: Date
    let isArchived: Bool
}

enum Canvas2StableIDs {
    static func artifactID(messageID: UUID, metadata: ArtifactMetadata) -> UUID {
        // Stable across recomputes so streaming updates don't invalidate past rows and sidebars.
        // Hash: messageID + filename + language
        var hasher = SHA256()
        hasher.update(data: Data(messageID.uuidString.utf8))
        hasher.update(data: Data("|".utf8))
        hasher.update(data: Data(metadata.filename.utf8))
        hasher.update(data: Data("|".utf8))
        hasher.update(data: Data(metadata.language.rawValue.utf8))
        let digest = hasher.finalize()
        let bytes = Array(digest)
        let uuidBytes = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuidBytes)
    }
}

// Note: ArtifactKind, ArtifactStatus, ArtifactAction, ArtifactPayload, and ArtifactMetadata
// are defined in Models/UI/ArtifactTypes.swift
