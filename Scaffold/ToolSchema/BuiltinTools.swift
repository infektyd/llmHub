// SCAFFOLD - Not compiled until activated

import Foundation

/// Example tool definitions using the new schema system
/// These replace the current ToolRegistry implementations

// MARK: - File Tools

struct ReadFileInput: ToolInput {
    let path: String
    let encoding: String?
    
    static var jsonSchema: JSONSchema {
        JSONSchema(
            type: "object",
            properties: [
                "path": .init(type: "string", description: "Absolute path to the file"),
                "encoding": .init(type: "string", description: "Text encoding (default: utf8)")
            ],
            required: ["path"],
            description: "Read the contents of a file"
        )
    }
}

struct WriteFileInput: ToolInput {
    let path: String
    let content: String
    let createDirectories: Bool?
    
    static var jsonSchema: JSONSchema {
        JSONSchema(
            type: "object",
            properties: [
                "path": .init(type: "string", description: "Absolute path to write to"),
                "content": .init(type: "string", description: "Content to write"),
                "createDirectories": .init(type: "boolean", description: "Create parent directories if needed")
            ],
            required: ["path", "content"],
            description: "Write content to a file"
        )
    }
}

// MARK: - Tool Registry (New Style)

enum BuiltinTools {
    static let readFile = Tool.define(
        name: "read_file",
        description: "Read the contents of a file at the specified path",
        input: ReadFileInput.self
    ) { input in
        // TODO: Implement with SandboxManager
        fatalError("Not implemented - scaffold only")
    }
    
    static let writeFile = Tool.define(
        name: "write_file", 
        description: "Write content to a file at the specified path",
        input: WriteFileInput.self
    ) { input in
        // TODO: Implement with SandboxManager
        fatalError("Not implemented - scaffold only")
    }
    
    static var all: [any Sendable] {
        [readFile, writeFile]
    }
}
