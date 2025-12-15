//
//  DatabaseQueryTool.swift
//  llmHub
//
//  Database query and manipulation tool
//

import Foundation
import OSLog

/// Database Query Tool conforming to the Tool protocol.
/// Executes SQL queries against configured databases.
/// Database Query Tool conforming to the Tool protocol.
/// Executes SQL queries against configured databases.
struct DatabaseQueryTool: Tool {
    let name = "database_query"
    let description = """
        Execute SQL queries against configured databases. \
        Supports SELECT, INSERT, UPDATE, DELETE operations. \
        Use this tool when you need to query or manipulate database data.
        """

    var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "query": ToolProperty(
                    type: .string,
                    description: "The SQL query to execute"
                ),
                "database": ToolProperty(
                    type: .string,
                    description: "Database identifier (default: use default database)"
                ),
                "parameters": ToolProperty(
                    type: .array,  // Note: Array support in ToolProperty might need verification/extensions, using generic array for now
                    description: "Optional query parameters for prepared statements"
                ),
                "limit": ToolProperty(
                    type: .integer,
                    description: "Maximum number of rows to return (default: 100)"
                ),
            ],
            required: ["query"]
        )
    }

    var permissionLevel: ToolPermissionLevel { .dangerous }
    var requiredCapabilities: [ToolCapability] { [.dbAccess] }
    var weight: ToolWeight { .heavy }
    var isCacheable: Bool { false }

    private let logger = Logger(subsystem: "com.llmhub", category: "DatabaseQueryTool")

    func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        throw ToolError.unavailable(
            reason:
                "Database connection not configured. Set up database credentials and connection strings in Settings > Tools > Database."
        )
    }
}
