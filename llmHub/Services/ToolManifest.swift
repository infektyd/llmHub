import Foundation

enum ToolManifest {
    static let startMarker = "<llmhub_tool_manifest>"
    static let endMarker = "</llmhub_tool_manifest>"

    static func systemPrompt(tools: [ToolDefinition], toolCallingAvailable: Bool) -> String {
        let header = """
        You are running inside llmHub, a native macOS/iOS app.

        Tool access is provided ONLY by llmHub and is limited to the tools listed in this message.
        Do not claim access to external tools (e.g. web browser, Python, filesystem, shell) unless you call an llmHub tool that provides that capability.
        """

        let toolCallingLine: String =
            toolCallingAvailable
            ? """
            Tool calls are available for this provider in llmHub. Use the provider's native tool/function calling mechanism when you need a tool result.
            """
            : """
            Tool calls are not available for this provider in llmHub. Do not output tool-call JSON or claim tool execution; respond with text only.
            """

        let toolList: String
        if tools.isEmpty {
            toolList = "Tools available in this conversation: (none)"
        } else {
            let lines = tools
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { tool in
                    let hint = whenToCallHint(for: tool.name)
                    if hint.isEmpty {
                        return "- \(tool.name): \(tool.description)"
                    }
                    return "- \(tool.name): \(tool.description) (When to call: \(hint))"
                }
                .joined(separator: "\n")
            toolList = "Tools available in this conversation:\n\(lines)"
        }

        let body = [header, toolCallingLine, toolList].joined(separator: "\n\n")
        return "\(startMarker)\n\(body)\n\(endMarker)"
    }

    static func upsert(into existingSystemPrompt: String, toolManifest: String) -> String {
        guard let startRange = existingSystemPrompt.range(of: startMarker),
            let endRange = existingSystemPrompt.range(of: endMarker)
        else {
            return "\(existingSystemPrompt)\n\n\(toolManifest)"
        }

        let replaceRange = startRange.lowerBound..<endRange.upperBound
        return existingSystemPrompt.replacingCharacters(in: replaceRange, with: toolManifest)
    }

    private static func whenToCallHint(for toolName: String) -> String {
        switch toolName.lowercased() {
        case "read_file":
            return "you must read a file to answer"
        case "edit_file":
            return "you need to create or modify a file"
        case "apply_patch":
            return "you can express changes as a unified diff patch"
        case "shell":
            return "you need to run terminal commands"
        case "http_request":
            return "you need to call an HTTP API"
        case "web_search":
            return "you need current web information"
        case "workspace":
            return "you need to list or manage workspace items"
        case "code_interpreter":
            return "you need to execute code to compute/verify"
        case "calculator":
            return "you need reliable arithmetic"
        default:
            return ""
        }
    }
}
