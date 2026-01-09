//
//  SchemaValidationTests.swift
//  llmHubTests
//
//  Created by Hans Axelsson on 12/12/25.
//

import XCTest

@testable import llmHub

final class SchemaValidationTests: XCTestCase {

    func testWorkspaceToolSchemaWithArrayItems() {
        let tool = WorkspaceTool()
        let schema = tool.parameters

        let extensionsProp = schema.properties["file_extensions"]
        XCTAssertNotNil(extensionsProp, "file_extensions property should exist")
        XCTAssertEqual(extensionsProp?.type, .array, "file_extensions should be an array")
        XCTAssertNotNil(extensionsProp?.items, "Array property MUST have 'items' defined")
        XCTAssertEqual(extensionsProp?.items?.type, .string, "Items should be of type string")
    }

    func testAllRegisteredToolsHaveValidSchemas() async {
        // Construct tool registry
        let tools: [any Tool] = [
            HTTPRequestTool(),
            ShellTool(),
            FileReaderTool(),
            CalculatorTool(),
            WebSearchTool(),
            FileEditorTool(),
            FilePatchTool(),
            WorkspaceTool()
        ]

        for tool in tools {
            let schema = tool.parameters
            validateSchema(schema, toolName: tool.name)
        }
    }

    private func validateSchema(_ schema: ToolParametersSchema, toolName: String) {
        for (key, property) in schema.properties {
            if property.type == .array {
                XCTAssertNotNil(
                    property.items,
                    "Tool '\(toolName)' property '\(key)' is strictly invalid: Array types must define 'items'."
                )
            }
            // Check recursive optional if needed (though ToolProperty structure is flat for items)
        }
    }
}
