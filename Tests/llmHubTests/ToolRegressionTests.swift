import Foundation
import Testing

@testable import llmHub

struct ToolRegressionTests {

    // MARK: - Web Search argument coercion

    final class MockURLProtocol: URLProtocol {
        nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.handler else {
                Issue.record("MockURLProtocol.handler not set")
                return
            }

            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private func makeMockSession(html: String) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]

        MockURLProtocol.handler = { request in
            let url = request.url ?? URL(string: "https://invalid")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(html.utf8))
        }

        return URLSession(configuration: config)
    }

    @MainActor
    private func makeExecutor(with tool: any Tool) async -> ToolExecutor {
        let registry = await ToolRegistry(tools: [tool])
        return ToolExecutor(registry: registry, environment: .current)
    }

    @MainActor
    private func makeContext() -> ToolContext {
        ToolContext(
            sessionID: UUID(),
            workspacePath: FileManager.default.temporaryDirectory,
            session: ToolSession()
        )
    }

    @Test @MainActor func webSearchAcceptsNumResultsStringInt() async {
        let html = """
        <div class=\"result\">
          <a rel=\"nofollow\" class=\"result__a\" href=\"https://example.com/1\">Title 1</a>
          <a class=\"result__snippet\">Snippet 1</a>
        </div>
        <div class=\"result\">
          <a rel=\"nofollow\" class=\"result__a\" href=\"https://example.com/2\">Title 2</a>
          <a class=\"result__snippet\">Snippet 2</a>
        </div>
        <div class=\"result\">
          <a rel=\"nofollow\" class=\"result__a\" href=\"https://example.com/3\">Title 3</a>
          <a class=\"result__snippet\">Snippet 3</a>
        </div>
        """

        let tool = WebSearchTool(session: makeMockSession(html: html))
        let executor = await makeExecutor(with: tool)

        let call = ToolCall(id: "t1", name: "web_search", input: #"{"query":"swift","num_results":"2"}"#)
        let result = await executor.executeSingle(call, context: makeContext())

        #expect(result.result.success)
        #expect(result.result.output.contains("Found 2 result"))
    }

    @Test @MainActor func webSearchAcceptsNumResultsStringFloatWhenIntegerValued() async {
        let html = """
        <div class=\"result\">
          <a rel=\"nofollow\" class=\"result__a\" href=\"https://example.com/1\">Title 1</a>
          <a class=\"result__snippet\">Snippet 1</a>
        </div>
        <div class=\"result\">
          <a rel=\"nofollow\" class=\"result__a\" href=\"https://example.com/2\">Title 2</a>
          <a class=\"result__snippet\">Snippet 2</a>
        </div>
        """

        let tool = WebSearchTool(session: makeMockSession(html: html))
        let executor = await makeExecutor(with: tool)

        let call = ToolCall(id: "t2", name: "web_search", input: #"{"query":"swift","num_results":"2.0"}"#)
        let result = await executor.executeSingle(call, context: makeContext())

        #expect(result.result.success)
        #expect(result.result.output.contains("Found 2 result"))
    }

    @Test @MainActor func webSearchRejectsNumResultsNonIntegerString() async {
        let tool = WebSearchTool(session: makeMockSession(html: ""))
        let executor = await makeExecutor(with: tool)

        let call = ToolCall(id: "t3", name: "web_search", input: #"{"query":"swift","num_results":"2.5"}"#)
        let result = await executor.executeSingle(call, context: makeContext())

        #expect(!result.result.success)
        #expect(result.result.output.contains("schema_validation_failed"))
        #expect(result.result.output.contains("num_results"))
    }

    // MARK: - Shell

    @Test(.enabled(if: {
        #if os(macOS)
            return true
        #else
            return false
        #endif
    }()))
    @MainActor func shellEchoCompletesQuicklyAndReturnsStdout() async throws {
        #if os(macOS)
            let tool = ShellTool()

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("llmHubTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let context = ToolContext(
                sessionID: UUID(),
                workspacePath: tempDir,
                session: ToolSession()
            )

            let args = ToolArguments([
                "command": "echo 'Shell command executed successfully'"
            ])

            let clock = ContinuousClock()
            let start = clock.now
            let result = try await tool.execute(arguments: args, context: context)
            let elapsed = clock.now - start

            #expect(result.success)
            #expect(result.output.contains("exit_code: 0"))
            #expect(result.output.contains("Shell command executed successfully"))
            #expect(elapsed < .seconds(1))
        #else
            throw SkipTest("Shell tool is not available on this platform")
        #endif
    }
}
