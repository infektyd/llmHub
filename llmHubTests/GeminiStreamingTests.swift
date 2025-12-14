import XCTest

@testable import llmHub

final class GeminiStreamingTests: XCTestCase {

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
}

