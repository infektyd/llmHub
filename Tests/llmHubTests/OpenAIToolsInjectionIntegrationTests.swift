#if canImport(XCTest)
import XCTest

@testable import llmHub

@MainActor
final class OpenAIToolsInjectionIntegrationTests: XCTestCase {
    func testGPT52_toolsInjection_acceptsWorkspaceSchema() async throws {
        guard ProcessInfo.processInfo.environment["LLMHUB_NETWORK_TESTS"] == "1" else {
            throw XCTSkip("Set LLMHUB_NETWORK_TESTS=1 to run live OpenAI verification.")
        }

        let env = ProcessInfo.processInfo.environment
        let apiKeyFromEnv = env["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey: String
        if let key = apiKeyFromEnv, !key.isEmpty {
            apiKey = key
        } else {
            let keychain = KeychainStore()
            guard let key = await keychain.apiKey(for: .openai), !key.isEmpty else {
                throw XCTSkip(
                    "OpenAI API key missing. Set OPENAI_API_KEY or configure it in llmHub Settings first."
                )
            }
            apiKey = key
        }

        guard let toolDef = ToolDefinition(from: WorkspaceTool()) else {
            XCTFail("Failed to create ToolDefinition from WorkspaceTool")
            return
        }
        let openAITool = OpenAITool(
            type: "function",
            function: OpenAIFunction(
                name: toolDef.name,
                description: toolDef.description,
                parameters: toolDef.inputSchema.mapValues { OpenAIJSONValue.from($0) }
            )
        )

        let manager = OpenAIManager(apiKey: apiKey)
        let request = try manager.makeResponsesRequest(
            messages: [
                OpenAIChatMessage(role: "user", content: .text("Reply with the single word: ok"))
            ],
            model: "gpt-5.2",
            tools: [openAITool],
            jsonMode: false
        )

        let (data, response) = try await LLMURLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            XCTFail("Missing HTTPURLResponse")
            return
        }

        let bodyText = String(data: data, encoding: .utf8) ?? ""
        if !(200...299).contains(http.statusCode) {
            XCTAssertFalse(
                bodyText.contains("Invalid schema for function"),
                "Schema rejected by OpenAI: \(bodyText)"
            )
            XCTFail("OpenAI request failed (\(http.statusCode)): \(bodyText)")
        }
    }
}
#endif
