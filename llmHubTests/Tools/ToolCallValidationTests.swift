import XCTest

@testable import llmHub

final class ToolCallValidationTests: XCTestCase {

    private struct EchoTool: Tool {
        nonisolated let name: String = "echo"
        nonisolated let description: String = "Echo a string."
        nonisolated let parameters: ToolParametersSchema = ToolParametersSchema(
            properties: [
                "text": ToolProperty(type: .string, description: "Text to echo")
            ],
            required: ["text"]
        )
        nonisolated let permissionLevel: ToolPermissionLevel = .safe

        nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
            ToolResult.success(arguments.string("text") ?? "")
        }
    }

    func testSchemaMismatchReturnsToolCallRejectedJSON() async throws {
        let registry = ToolRegistry(tools: [EchoTool()])
        let executor = ToolExecutor(registry: registry, environment: .current)

        let call = ToolCall(id: "call_1", name: "echo", input: #"{}"#)
        let context = ToolContext(
            sessionID: UUID(),
            workspacePath: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            session: ToolSession()
        )

        let result = await executor.executeSingle(call, context: context)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.contains(#""type":"tool_call_rejected""#))
        XCTAssertTrue(result.output.contains(#""reason":"schema_validation_failed""#))
        XCTAssertTrue(result.output.contains("Missing required property"))
    }

    func testUnknownToolReturnsToolCallRejectedJSON() async throws {
        let registry = ToolRegistry(tools: [])
        let executor = ToolExecutor(registry: registry, environment: .current)

        let call = ToolCall(id: "call_2", name: "does_not_exist", input: #"{}"#)
        let context = ToolContext(
            sessionID: UUID(),
            workspacePath: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            session: ToolSession()
        )

        let result = await executor.executeSingle(call, context: context)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.contains(#""type":"tool_call_rejected""#))
        XCTAssertTrue(result.output.contains(#""reason":"unknown_tool""#))
    }
}
