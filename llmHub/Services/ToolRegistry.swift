import Foundation

/// Protocol defining a tool that can be executed by the LLM.
protocol Tool: Sendable {
    /// The unique identifier of the tool.
    nonisolated var id: String { get }
    /// The name of the tool (used by the LLM to call it).
    nonisolated var name: String { get }
    /// A description of what the tool does.
    nonisolated var description: String { get }
    /// The JSON schema describing the input arguments.
    nonisolated var inputSchema: [String: Any] { get }

    /// Executes the tool with the provided arguments.
    /// - Parameter input: A dictionary of arguments matching the schema.
    /// - Returns: The result of the execution as a String.
    nonisolated func execute(input: [String: Any]) async throws -> String
}

/// A registry for managing available tools.
struct ToolRegistry {
    /// Dictionary of registered tools, keyed by name.
    private(set) var tools: [String: any Tool] = [:]

    /// Initializes a new `ToolRegistry`.
    /// - Parameter tools: An array of tools to register initially.
    nonisolated init(tools: [any Tool] = []) {
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }

    /// Retrieves a tool by its name.
    /// - Parameter name: The name of the tool.
    /// - Returns: The tool instance, or nil if not found.
    func tool(named name: String) -> (any Tool)? {
        tools[name]
    }

    /// Registers a new tool.
    /// - Parameter tool: The tool to register.
    mutating func register(_ tool: any Tool) {
        tools[tool.name] = tool
    }

    /// Get all registered tools.
    var allTools: [any Tool] {
        Array(tools.values)
    }

    /// Get tool schemas formatted for LLM function calling.
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
    /// Create a registry with all default tools.
    /// Must be called from MainActor context due to `CodeInterpreterTool` initialization which may access MainActor isolated properties.
    /// - Returns: A populated `ToolRegistry`.
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

    /// Synchronous factory for use in nonisolated contexts.
    /// Uses `MainActor.assumeIsolated` for safe synchronous access when called from MainActor.
    /// Falls back to minimal registry when called from other contexts.
    /// - Returns: A `ToolRegistry`.
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
/// A simple calculator tool for evaluating mathematical expressions.
struct CalculatorTool: Tool {
    nonisolated let id = "calculator"
    nonisolated let name = "calculator"
    nonisolated let description =
        "Evaluates mathematical expressions. Use this for any math questions."

    nonisolated init() {}

    nonisolated var inputSchema: [String: Any] {
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

    nonisolated func execute(input: [String: Any]) async throws -> String {
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

/// Errors related to tool execution.
enum ToolError: LocalizedError {
    /// The input arguments were invalid.
    case invalidInput
    /// The tool execution failed with a specific reason.
    case executionFailed(String)

    /// A localized description of the error.
    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Invalid tool input arguments"
        case .executionFailed(let reason):
            return "Tool execution failed: \(reason)"
        }
    }
}
