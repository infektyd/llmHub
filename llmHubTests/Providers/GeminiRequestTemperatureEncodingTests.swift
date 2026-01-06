import XCTest

@testable import llmHub

final class GeminiRequestTemperatureEncodingTests: XCTestCase {

    func testGeminiManagerEncodesTemperatureWhenProvided() throws {
        // We only validate JSON encoding; no network is performed.
        let manager = GeminiManager(apiKey: "test")

        let request = try manager.makeGenerateContentRequest(
            prompt: "hi",
            model: "gemini-2.0-flash-001",
            temperature: 0.0,
            history: [],
            tools: nil,
            maxOutputTokens: 128,
            stream: false
        )

        let body = try XCTUnwrap(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body, options: []) as? [String: Any]
        let generationConfig = json?["generationConfig"] as? [String: Any]

        XCTAssertEqual(generationConfig?["temperature"] as? Double, 0.0)
        XCTAssertEqual(generationConfig?["maxOutputTokens"] as? Int, 128)
    }
}
