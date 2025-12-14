// Services/ToolRegistry.swift
// Thread-safe tool registration and discovery

import Foundation
import OSLog

/// Actor-based registry for tool management.
actor ToolRegistry {
    private let logger = Logger(subsystem: "com.llmhub", category: "ToolRegistry")
    private var tools: [String: any Tool] = [:]

    init(tools: [any Tool] = []) async {
        for tool in tools {
            let name = tool.name
            self.self.tools[name] = tool
        }
    }

    func register(_ tool: any Tool) async {
        let name = tool.name
        self.tools[name] = tool
    }

    func register(_ tools: [any Tool]) async {
        for tool in tools {
            let name = tool.name
            self.tools[name] = tool
        }
    }

    func unregister(name: String) {
        tools.removeValue(forKey: name)
    }

    func tool(named name: String) -> (any Tool)? {
        tools[name]
    }

    func tool(named name: String, in environment: ToolEnvironment) -> (any Tool)? {
        guard let tool = tools[name] else { return nil }
        guard tool.availability(in: environment).isAvailable else { return nil }
        return tool
    }

    func availableTools(in environment: ToolEnvironment) -> [any Tool] {
        tools.values
            .filter { $0.availability(in: environment).isAvailable }
            .sorted { $0.name < $1.name }
    }

    func allTools() -> [any Tool] {
        tools.values.sorted { $0.name < $1.name }
    }


    /// Export schemas for LLM API injection.
    func exportSchemas(for environment: ToolEnvironment) -> [[String: Any]] {
        availableTools(in: environment).compactMap { tool in
            if let invalidArrayProperty = tool.parameters.firstInvalidArrayPropertyName() {
                let message =
                    "Invalid schema for function '\(tool.name)': In context=('properties','\(invalidArrayProperty)'), array schema missing items."
                #if DEBUG
                    assertionFailure(message)
                #endif
                logger.error("\(message, privacy: .public) Tool will be omitted from export.")
                return nil
            }
            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.parameters.toDictionary(),
                ],
            ]
        }
    }
}

// MARK: - Schema Export

extension ToolParametersSchema {
    nonisolated func firstInvalidArrayPropertyName() -> String? {
        for (name, property) in properties {
            if property.type == .array, property.items == nil {
                return name
            }
        }
        return nil
    }
}

extension ToolParametersSchema {
    nonisolated func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["type": type]
        dict["properties"] = properties.mapValues { $0.toDictionary() }
        if !required.isEmpty {
            dict["required"] = required
        }
        return dict
    }
}

extension ToolProperty {
    nonisolated func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type.rawValue,
            "description": description,
        ]
        if let enums = enumValues {
            dict["enum"] = enums
        }
        if let items = items {
            dict["items"] = items.toDictionary()
        }
        return dict
    }
}
