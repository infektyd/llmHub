#if canImport(XCTest)
import XCTest

@testable import llmHub

@MainActor
final class ToolSchemaValidationTests: XCTestCase {

    // MARK: - Provider ID Normalization

    private struct StubProvider: LLMProvider {
        nonisolated let id: String
        nonisolated let name: String
        nonisolated let endpoint: URL = URL(string: "https://example.com")!
        nonisolated let supportsStreaming: Bool = false
        nonisolated let supportsToolCalling: Bool = false
        nonisolated let availableModels: [LLMModel] = []
        nonisolated var defaultHeaders: [String: String] { get async { [:] } }
        nonisolated let pricing: PricingMetadata = PricingMetadata(
            inputPer1KUSD: 0, outputPer1KUSD: 0, currency: "USD"
        )
        nonisolated var isConfigured: Bool { get async { true } }

        func fetchModels() async throws -> [LLMModel] { [] }
        func buildRequest(
            messages: [ChatMessage],
            model: String,
            tools: [ToolDefinition]?,
            options: LLMRequestOptions
        ) async throws -> URLRequest {
            URLRequest(url: endpoint)
        }
        func streamResponse(from request: URLRequest) -> AsyncThrowingStream<ProviderEvent, Error> {
            AsyncThrowingStream { $0.finish() }
        }
        func parseTokenUsage(from response: Data) throws -> TokenUsage? { nil }
    }

    func testPersistedOpenAIResolvesToCanonicalProvider() async throws {
        let registry = ProviderRegistry(providerBuilders: [
            { StubProvider(id: "openai", name: "OpenAI") },
            { StubProvider(id: "google", name: "Google AI (Gemini)") }
        ])

        let provider = try registry.provider(for: "OpenAI")
        let canonicalID = await MainActor.run { provider.id }
        XCTAssertEqual(canonicalID, "openai")
    }

    // MARK: - Gemini SSE Streaming Robustness

    func testSSEParserBuffersMultilineGeminiEvent() throws {
        // Fixture: a single SSE event where JSON is split across multiple `data:` lines.
        // This previously caused per-line decoders to fail on partial JSON fragments.
        let sse =
            """
            data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"workspace","args":{"operation":"list","path":"/"}}}]},"finishReason":
            data: "MALFORMED_FUNCTION_CALL"}]}


            """

        // Feed bytes in two chunks to simulate fragmented network delivery.
        let bytes = Array(sse.utf8)
        let splitIndex = bytes.count / 2

        var parser = SSEEventParser()
        XCTAssertTrue(parser.append(Data(bytes[0..<splitIndex])).isEmpty)

        let payloads = parser.append(Data(bytes[splitIndex..<bytes.count]))
        XCTAssertEqual(payloads.count, 1)

        let data = try XCTUnwrap(payloads.first?.data(using: .utf8))
        let decoded = try JSONDecoder().decode(GenerationResponse.self, from: data)
        XCTAssertEqual(decoded.candidates?.first?.finishReason, "MALFORMED_FUNCTION_CALL")
    }

    // MARK: - Tool Call Rejection (Schema Validation)

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
        let registry = await ToolRegistry(tools: [EchoTool()])
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
        let registry = await ToolRegistry(tools: [])
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

    func testWorkspaceToolSchema_fileExtensionsHasStringItems() throws {
        let schema = WorkspaceTool().parameters.toDictionary()
        let props = try XCTUnwrap(schema["properties"] as? [String: Any])
        let fileExtensions = try XCTUnwrap(props["file_extensions"] as? [String: Any])
        XCTAssertEqual(fileExtensions["type"] as? String, "array")

        let items = try XCTUnwrap(fileExtensions["items"] as? [String: Any])
        XCTAssertEqual(items["type"] as? String, "string")

        let jsonData = try JSONSerialization.data(
            withJSONObject: fileExtensions,
            options: [.prettyPrinted, .sortedKeys]
        )
        let json = try XCTUnwrap(String(data: jsonData, encoding: .utf8))
        let attachment = XCTAttachment(string: json)
        attachment.name = "workspace.file_extensions.schema.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

#endif
