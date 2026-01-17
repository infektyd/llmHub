//
//  ToolsEnabledPolicy.swift
//  llmHub
//
//  Dynamic tool enablement policy and heuristics for request building.
//

import Foundation

enum ToolsEnabledPolicy: String, Sendable {
    case zen
    case workhorse
}

struct ToolsEnabledPolicyResolver {
    static let userDefaultsKey = "llmhub.tools.enabledPolicy"
    static let environmentKey = "LLMHUB_TOOLS_POLICY"

    static func resolve(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ToolsEnabledPolicy {
        if let raw = environment[environmentKey]?.lowercased(),
            let policy = ToolsEnabledPolicy(rawValue: raw)
        {
            return policy
        }
        if let raw = defaults.string(forKey: userDefaultsKey)?.lowercased(),
            let policy = ToolsEnabledPolicy(rawValue: raw)
        {
            return policy
        }
        return .zen
    }
}

struct ToolRelevanceHeuristics {
    static let coreTools: Set<String> = ["calculator"]

    /// Artifact tools that should always be available when attachments are present.
    static let artifactTools: Set<String> = [
        "artifact_list", "artifact_open", "artifact_read_text", "artifact_describe_image",
    ]

    static func allowedToolNames(
        policy: ToolsEnabledPolicy,
        userMessage: String,
        hasKnownAttachments: Bool = false
    ) -> Set<String> {
        switch policy {
        case .workhorse:
            return []
        case .zen:
            var relevant = relevantToolNames(for: userMessage)
            // Hard signal: always include artifact tools when attachments present
            if hasKnownAttachments {
                relevant.formUnion(artifactTools)
            }
            return relevant.isEmpty ? coreTools : coreTools.union(relevant)
        }
    }

    static func relevantToolNames(for message: String) -> Set<String> {
        let normalized = message.lowercased()
        let tokens = Set(
            normalized
                .split { !$0.isLetter && !$0.isNumber && $0 != "_" }
                .map(String.init)
        )

        func hasAnyToken(_ candidates: [String]) -> Bool {
            candidates.contains(where: { tokens.contains($0) })
        }

        func containsPhrase(_ phrase: String) -> Bool {
            normalized.contains(phrase)
        }

        var tools = Set<String>()

        let fileKeywords = [
            "file", "files", "folder", "folders", "directory", "directories", "path", "paths",
            "workspace", "repo", "project", "artifact", "artifacts", "diff", "patch", "grep",
        ]
        let filePhrases = [
            "read file", "open file", "edit file", "apply patch", "unified diff", "list files",
            "search files", "search in files", "file contents", "workspace",
        ]
        let hasFileContext =
            hasAnyToken(fileKeywords) || filePhrases.contains(where: containsPhrase)
            || normalized.contains("/")
            || normalized.contains(".swift")
            || normalized.contains(".md")
            || normalized.contains(".json")
            || normalized.contains(".yml")
            || normalized.contains(".yaml")
            || normalized.contains(".txt")
        if hasFileContext {
            tools.formUnion(["read_file", "file_editor", "file_patch", "workspace"])
        }

        let calcKeywords = [
            "calculate", "calc", "math", "sum", "average", "avg", "mean", "median", "percent",
            "percentage", "ratio", "total",
        ]
        if hasAnyToken(calcKeywords) || containsPhrase("calculate ") {
            tools.insert("calculator")
        }

        let plotKeywords = [
            "plot", "graph", "chart", "visualize", "visualization", "histogram", "scatter",
            "line", "bar", "pie", "heatmap",
        ]
        if hasAnyToken(plotKeywords) {
            tools.insert("data_visualization")
        }

        let webQualifiers = [
            "web", "internet", "online", "news", "latest", "current", "google", "bing",
            "duckduckgo",
        ]
        let webSearchVerbs = ["search", "lookup"]
        let wantsWebSearch =
            hasAnyToken(webQualifiers) || (hasAnyToken(webSearchVerbs) && !hasFileContext)
        if wantsWebSearch {
            tools.insert("web_search")
        }

        let httpKeywords = [
            "http", "https", "api", "endpoint", "curl", "request", "fetch", "webhook", "rest",
            "graphql",
        ]
        if hasAnyToken(httpKeywords) {
            tools.insert("http_request")
        }

        let shellKeywords = ["shell", "terminal", "command", "bash", "zsh", "cli"]
        if hasAnyToken(shellKeywords) {
            tools.insert("shell")
        }

        let codeKeywords = [
            "code", "python", "javascript", "js", "typescript", "ts", "swift", "dart", "script",
            "program", "programming",
        ]
        if hasAnyToken(codeKeywords) || containsPhrase("run code") || containsPhrase("execute code")
        {
            tools.insert("code_interpreter")
        }

        return tools
    }
}
