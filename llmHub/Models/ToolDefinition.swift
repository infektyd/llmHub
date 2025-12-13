//
//  ToolDefinition.swift
//  llmHub
//
//  Created by Assistant on 12/10/25.
//

import Foundation
import OSLog

/// Tool definition for LLM function calling.
struct ToolDefinition: Sendable {
    nonisolated private static let logger = Logger(
        subsystem: "com.llmhub",
        category: "ToolDefinition"
    )

    /// The name of the tool.
    let name: String
    /// A description of what the tool does.
    let description: String
    /// The JSON schema for the tool's input arguments.
    nonisolated(unsafe) let inputSchema: [String: Any]

    /// Initializes a `ToolDefinition` from a generic tool.
    /// - Parameter tool: The tool to define.
    nonisolated init?(from tool: any Tool) {
        self.name = tool.name
        self.description = tool.description

        // Convert ToolParametersSchema to a JSON dictionary without relying on Encodable,
        // since the project uses default main-actor isolation.
        if let invalidArrayProperty = tool.parameters.firstInvalidArrayPropertyName() {
            let message =
                "Invalid schema for function '\(tool.name)': In context=('properties','\(invalidArrayProperty)'), array schema missing items."
            #if DEBUG
                assertionFailure(message)
            #endif
            Self.logger.error("\(message, privacy: .public) Tool will be omitted from tool injection.")
            return nil
        }
        self.inputSchema = tool.parameters.toDictionary()
    }

    /// Memberwise initializer
    nonisolated init(name: String, description: String, inputSchema: [String: Any]) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}
