import XCTest

@testable import llmHub

@MainActor
final class GeminiRequestEncodingTests: XCTestCase {

    private func decodeJSONObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @available(iOS 26.1, macOS 26.1, *)
    func testGemini3EncodesThinkingLevelNestedUnderThinkingConfigCamelCase() throws {
        let options = LLMRequestOptions(thinkingPreference: .on, thinkingBudgetTokens: 1024)
        let thinkingConfig = try GeminiManager.buildThinkingConfig(
            model: "gemini-3-flash-preview",
            options: options
        )

        var generationConfig = GenerationConfig()
        generationConfig.maxOutputTokens = 8192
        generationConfig.thinkingConfig = thinkingConfig

        let payload = GenerateContentRequest(
            contents: [Content(role: "user", parts: [.text("Hello")])],
            generationConfig: generationConfig,
            tools: nil
        )

        let body = try JSONEncoder().encode(payload)
        let json = try decodeJSONObject(body)

        XCTAssertNil(json["generation_config"])
        let generationConfigJSON = try XCTUnwrap(json["generationConfig"] as? [String: Any])
        XCTAssertNil(generationConfigJSON["thinking_level"])
        let thinkingConfigJSON = try XCTUnwrap(generationConfigJSON["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinkingConfigJSON["thinkingLevel"] as? String, "high")
        XCTAssertNil(thinkingConfigJSON["thinkingBudget"])

        let decoded = try JSONDecoder().decode(GenerateContentRequest.self, from: body)
        XCTAssertEqual(decoded.generationConfig?.thinkingConfig?.thinkingLevel?.rawValue, "high")
        XCTAssertNil(decoded.generationConfig?.thinkingConfig?.thinkingBudget)
    }

    @available(iOS 26.1, macOS 26.1, *)
    func testGemini25EncodesThinkingBudgetOnly() throws {
        let options = LLMRequestOptions(thinkingPreference: .on, thinkingBudgetTokens: 1234)
        let thinkingConfig = try GeminiManager.buildThinkingConfig(
            model: "gemini-2.5-flash",
            options: options
        )

        var generationConfig = GenerationConfig()
        generationConfig.maxOutputTokens = 8192
        generationConfig.thinkingConfig = thinkingConfig

        let payload = GenerateContentRequest(
            contents: [Content(role: "user", parts: [.text("Hello")])],
            generationConfig: generationConfig,
            tools: nil
        )

        let body = try JSONEncoder().encode(payload)
        let json = try decodeJSONObject(body)
        let generationConfigJSON = try XCTUnwrap(json["generationConfig"] as? [String: Any])
        let thinkingConfigJSON = try XCTUnwrap(generationConfigJSON["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinkingConfigJSON["thinkingBudget"] as? Int, 1234)
        XCTAssertNil(thinkingConfigJSON["thinkingLevel"])

        let decoded = try JSONDecoder().decode(GenerateContentRequest.self, from: body)
        XCTAssertEqual(decoded.generationConfig?.thinkingConfig?.thinkingBudget, 1234)
        XCTAssertNil(decoded.generationConfig?.thinkingConfig?.thinkingLevel)
    }

    @available(iOS 26.1, macOS 26.1, *)
    func testNonThinkingModelOmitsThinkingConfigEvenWhenPreferenceOn() throws {
        let options = LLMRequestOptions(thinkingPreference: .on, thinkingBudgetTokens: 999)
        let thinkingConfig = try GeminiManager.buildThinkingConfig(
            model: "gemini-1.5-pro",
            options: options
        )

        var generationConfig = GenerationConfig()
        generationConfig.maxOutputTokens = 8192
        generationConfig.thinkingConfig = thinkingConfig

        let payload = GenerateContentRequest(
            contents: [Content(role: "user", parts: [.text("Hello")])],
            generationConfig: generationConfig,
            tools: nil
        )

        let body = try JSONEncoder().encode(payload)
        let json = try decodeJSONObject(body)
        let generationConfigJSON = try XCTUnwrap(json["generationConfig"] as? [String: Any])
        XCTAssertNotNil(generationConfigJSON["maxOutputTokens"])
        XCTAssertNil(generationConfigJSON["thinkingConfig"])

        let decoded = try JSONDecoder().decode(GenerateContentRequest.self, from: body)
        XCTAssertNil(decoded.generationConfig?.thinkingConfig)
    }

    @available(iOS 26.1, macOS 26.1, *)
    func testThinkingLevelAndBudgetAreMutuallyExclusive() throws {
        let invalid = ThinkingConfig(includeThoughts: nil, thinkingBudget: 1, thinkingLevel: .high)
        XCTAssertThrowsError(try GeminiManager.validateThinkingConfig(invalid))
    }

    @available(iOS 26.1, macOS 26.1, *)
    func testGemini3FlashAllowsMediumThinkingLevelHint() throws {
        let options = LLMRequestOptions(thinkingPreference: .on, thinkingBudgetTokens: nil, thinkingLevelHint: "medium")
        let thinkingConfig = try XCTUnwrap(
            GeminiManager.buildThinkingConfig(model: "gemini-3-flash-preview", options: options)
        )
        XCTAssertEqual(thinkingConfig.thinkingLevel?.rawValue, "medium")
    }

    @available(iOS 26.1, macOS 26.1, *)
    func testGemini3ProRejectsMediumThinkingLevelHint() throws {
        let options = LLMRequestOptions(thinkingPreference: .on, thinkingBudgetTokens: nil, thinkingLevelHint: "medium")
        XCTAssertThrowsError(
            try GeminiManager.buildThinkingConfig(model: "gemini-3-pro-preview", options: options)
        )
    }

    @available(iOS 26.1, macOS 26.1, *)
    func testGemini25RejectsThinkingLevelHint() throws {
        let options = LLMRequestOptions(thinkingPreference: .on, thinkingBudgetTokens: 100, thinkingLevelHint: "low")
        XCTAssertThrowsError(
            try GeminiManager.buildThinkingConfig(model: "gemini-2.5-pro", options: options)
        )
    }

    @available(iOS 26.1, macOS 26.1, *)
    func testDecodesFunctionCallWithThoughtSignatureOnSamePart() throws {
        let json = """
        {
          "candidates": [
            {
              "content": {
                "role": "model",
                "parts": [
                  {
                    "functionCall": { "name": "doThing", "args": { "x": 1 } },
                    "thoughtSignature": "c2lnbmF0dXJl"
                  }
                ]
              }
            }
          ]
        }
        """

        let decoded = try JSONDecoder().decode(GenerationResponse.self, from: Data(json.utf8))
        let part = try XCTUnwrap(decoded.candidates?.first?.content.parts.first)
        XCTAssertEqual(part.functionCall?.name, "doThing")
        XCTAssertEqual(part.thoughtSignature, "c2lnbmF0dXJl")
    }

    @available(iOS 26.1, macOS 26.1, *)
    func testEncodesFunctionCallWithThoughtSignatureOnSamePart() throws {
        let args: [String: GeminiJSONValue] = ["x": .number(1)]

        let payload = GenerateContentRequest(
            contents: [
                Content(
                    role: "model",
                    parts: [
                        .functionCall(
                            FunctionCall(name: "doThing", args: args),
                            thoughtSignature: "c2lnbmF0dXJl"
                        )
                    ]
                )
            ],
            generationConfig: nil,
            tools: nil
        )

        let data = try JSONEncoder().encode(payload)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let contents = try XCTUnwrap(root["contents"] as? [[String: Any]])
        let first = try XCTUnwrap(contents.first)
        let parts = try XCTUnwrap(first["parts"] as? [[String: Any]])
        let part = try XCTUnwrap(parts.first)
        XCTAssertEqual(part["thoughtSignature"] as? String, "c2lnbmF0dXJl")
        XCTAssertNotNil(part["functionCall"])
    }

    @available(iOS 26.1, macOS 26.1, *)
    func testGoogleHistoryBuilderPreservesThoughtSignatureOnFunctionCallPart() throws {
        let call = ToolCall(
            id: "call_1",
            name: "doThing",
            input: "{\"x\":1}",
            geminiThoughtSignature: "c2lnbmF0dXJl"
        )

        let assistant = ChatMessage(
            id: UUID(),
            role: .assistant,
            content: "",
            thoughtProcess: nil,
            parts: [],
            attachments: [],
            createdAt: Date(),
            codeBlocks: [],
            tokenUsage: nil,
            costBreakdown: nil,
            toolCallID: nil,
            toolCalls: [call]
        )

        let contents = GoogleAIProvider.buildHistoryContents(
            historyMessages: [assistant][...],
            toolNameByCallID: [:]
        )

        let content = try XCTUnwrap(contents.first)
        XCTAssertEqual(content.role, "model")
        let part = try XCTUnwrap(content.parts.first)
        XCTAssertEqual(part.functionCall?.name, "doThing")
        XCTAssertEqual(part.thoughtSignature, "c2lnbmF0dXJl")
    }
}
