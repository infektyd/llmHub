import XCTest

@testable import llmHub

final class GeminiResponseAssemblyTests: XCTestCase {
    func testAssembledTextConcatenatesAllPartsForCandidate() throws {
        // Captured fixture JSON: multi-part content with multiple candidates.
        let fixture =
            """
            {
              "candidates": [
                {
                  "content": {
                    "role": "model",
                    "parts": [
                      { "text": "Hello " },
                      { "text": "world" },
                      { "text": "!" }
                    ]
                  },
                  "finishReason": "STOP"
                },
                {
                  "content": {
                    "role": "model",
                    "parts": [
                      { "text": "IGNORE" }
                    ]
                  },
                  "finishReason": "STOP"
                }
              ],
              "usageMetadata": {
                "promptTokenCount": 5,
                "candidatesTokenCount": 3,
                "totalTokenCount": 8
              }
            }
            """

        let data = try XCTUnwrap(fixture.data(using: .utf8))
        let decoded = try JSONDecoder().decode(GenerationResponse.self, from: data)

        XCTAssertEqual(decoded.candidateCount, 2)
        XCTAssertEqual(decoded.partCountsByCandidate, [3, 1])
        XCTAssertEqual(decoded.assembledText(candidateIndex: 0), "Hello world!")
        XCTAssertEqual(decoded.assembledText(candidateIndex: 1), "IGNORE")
    }
}
