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
    
    init(tools: [any Tool] = []) {
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }
    
    func tool(named name: String) -> (any Tool)? {
        tools[name]
    }
    
    mutating func register(_ tool: any Tool) {
        tools[tool.name] = tool
    }
}

extension ToolRegistry: Sendable {}

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
                    "description": "The mathematical expression to evaluate (e.g., '5 * 5 + 2')"
                ]
            ],
            "required": ["expression"]
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
        case .invalidInput: "Invalid tool input arguments"
        case .executionFailed(let reason): "Tool execution failed: \(reason)"
        }
    }
}
