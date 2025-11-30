import Foundation

protocol Tool: Sendable {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    var inputSchema: [String: Any] { get }

    func execute(input: [String: Any]) async throws -> String
}

struct ToolRegistry {
    private(set) var tools: [String: any Tool] = [:]

    nonisolated init(tools: [any Tool] = []) {
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }

    func tool(named name: String) -> (any Tool)? {
        tools[name]
    }

    mutating func register(_ tool: any Tool) {
        tools[tool.name] = tool
    }

    /// Get all registered tools
    var allTools: [any Tool] {
        Array(tools.values)
    }

    /// Get tool schemas for LLM function calling
    var toolSchemas: [[String: Any]] {
        allTools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.inputSchema,
            ]
        }
    }
}

extension ToolRegistry: Sendable {}

// MARK: - Default Registry Factory

extension ToolRegistry {
    /// Create a registry with all default tools
    /// Must be called from MainActor context due to CodeInterpreterTool initialization
    @MainActor
    static func defaultRegistry() -> ToolRegistry {
        var registry = ToolRegistry()

        // Register Calculator
        registry.register(CalculatorTool())

        // Register Code Interpreter with settings from UserDefaults
        let codeInterpreter = CodeInterpreterTool()
        if let modeString = UserDefaults.standard.string(forKey: "codeInterpreter.securityMode"),
            let mode = CodeSecurityMode(rawValue: modeString)
        {
            codeInterpreter.securityMode = mode
        }
        codeInterpreter.timeoutSeconds = UserDefaults.standard.integer(
            forKey: "codeInterpreter.timeout")
        if codeInterpreter.timeoutSeconds == 0 {
            codeInterpreter.timeoutSeconds = 30  // Default
        }
        registry.register(codeInterpreter)

        // Register Web Search
        registry.register(WebSearchTool())

        // Register File Reader
        registry.register(FileReaderTool())

        // Register File Editor with settings from UserDefaults
        let fileEditor = FileEditorTool()
        if let modeString = UserDefaults.standard.string(forKey: "fileEditor.securityMode"),
            let mode = FileSecurityMode(rawValue: modeString)
        {
            fileEditor.securityMode = mode
        }
        registry.register(fileEditor)

        return registry
    }

    /// Synchronous factory for use in nonisolated contexts
    /// Uses MainActor.assumeIsolated for safe synchronous access when called from MainActor
    /// Falls back to minimal registry when called from other contexts
    @inline(__always)
    nonisolated static func createDefaultRegistrySync() -> ToolRegistry {
        // If we're already on the main actor, we can safely call the @MainActor method
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                defaultRegistry()
            }
        }
        // Fallback: return minimal registry without MainActor-dependent tools
        // This path should rarely be hit in practice since ChatService is typically
        // initialized on the main thread
        return ToolRegistry(tools: [CalculatorTool()])
    }
}

// Basic Calculator Tool
struct CalculatorTool: Tool {
    let id = "calculator"
    let name = "calculator"
    let description = "Evaluates mathematical expressions. Use this for any math questions."

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "expression": [
                    "type": "string",
                    "description": "The mathematical expression to evaluate (e.g., '5 * 5 + 2')",
                ]
            ],
            "required": ["expression"],
        ]
    }

    func execute(input: [String: Any]) async throws -> String {
        guard let expression = input["expression"] as? String else {
            throw ToolError.invalidInput
        }

        // Using NSExpression for basic safety (avoiding full eval)
        let expr = NSExpression(format: expression)
        if let result = expr.expressionValue(with: nil, context: nil) as? NSNumber {
            return result.stringValue
        } else {
            throw ToolError.executionFailed("Could not evaluate expression")
        }
    }
}

enum ToolError: LocalizedError {
    case invalidInput
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Invalid tool input arguments"
        case .executionFailed(let reason):
            return "Tool execution failed: \(reason)"
        }
    }
}
