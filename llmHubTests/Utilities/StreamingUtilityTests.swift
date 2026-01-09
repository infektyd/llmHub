import XCTest

@testable import llmHub

final class StreamingUtilityTests: XCTestCase {

    func testSSEEventFrameParserCapturesEventAndData() {
        let sse =
            """
            event: response.output_text.delta
            data: {"type":"response.output_text.delta","delta":"Hi"}


            """

        var parser = SSEEventFrameParser()
        let bytes = Array(sse.utf8)
        let split = bytes.count / 2

        XCTAssertTrue(parser.append(Data(bytes[0..<split])).isEmpty)
        let frames = parser.append(Data(bytes[split..<bytes.count]))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.event, "response.output_text.delta")
        XCTAssertEqual(frames.first?.data, #"{"type":"response.output_text.delta","delta":"Hi"}"#)
    }

    func testThinkTagStreamExtractorSeparatesVisibleAndThinking() {
        var extractor = ThinkTagStreamExtractor()

        let first = extractor.process(delta: "Hello <think>")
        XCTAssertEqual(first.visible, "Hello ")
        XCTAssertEqual(first.thinking, "")

        let second = extractor.process(delta: "foo</think> world")
        XCTAssertEqual(second.thinking, "foo")

        let flushed = extractor.flush()
        XCTAssertEqual(flushed.visible, " world")
        XCTAssertEqual(flushed.thinking, "")
    }

    func testPartialToolCallAssemblerWaitsForValidJSON() {
        var assembler = PartialToolCallAssembler()

        assembler.ingest(index: 0, id: "call_1", name: "echo", argumentsDelta: "{")
        XCTAssertTrue(assembler.finalizeAll().isEmpty)

        assembler.ingest(index: 0, id: "call_1", name: nil, argumentsDelta: "\"text\":\"hi\"")
        XCTAssertTrue(assembler.finalizeAll().isEmpty)

        assembler.ingest(index: 0, id: "call_1", name: nil, argumentsDelta: "}")
        let calls = assembler.finalizeAll()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.id, "call_1")
        XCTAssertEqual(calls.first?.name, "echo")
        XCTAssertEqual(calls.first?.input, #"{"text":"hi"}"#)
    }
}
