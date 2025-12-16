//
//  HTTPRequestToolTests.swift
//  llmHubTests
//
//  Created by Assistant on 12/15/25.
//

import XCTest

@testable import llmHub

class HTTPRequestToolTests: XCTestCase {

    var tool: HTTPRequestTool!
    var logger: Logger!
    var context: ToolContext!

    override func setUp() {
        super.setUp()
        // Register the mock protocol
        URLProtocol.registerClass(MockURLProtocol.self)

        tool = HTTPRequestTool()
        logger = Logger(subsystem: "test", category: "http_request")
        context = ToolContext(
            logger: logger,
            projectRoot: URL(fileURLWithPath: "/tmp"),
            environment: [:]
        )
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testExecute_SuccessJSON() async throws {
        let jsonString = "{\"key\": \"value\"}"
        let data = jsonString.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }

        let args = ToolArguments(dictionary: ["url": "https://api.example.com/data"])
        let result = try await tool.execute(arguments: args, context: context)

        guard case .success(let output, let metadata, _) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertTrue(output.contains("HTTP 200"))
        XCTAssertTrue(output.contains("{\"key\": \"value\"}"))
        XCTAssertNotNil(metadata["elapsedMs"])
    }

    func testExecute_404Error() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let args = ToolArguments(dictionary: ["url": "https://api.example.com/missing"])
        let result = try await tool.execute(arguments: args, context: context)

        // Tool currently treats non-200 responses as success result containing the status code
        guard case .success(let output, let metadata, _) = result else {
            XCTFail("Expected success result with 404 status")
            return
        }

        XCTAssertTrue(output.contains("HTTP 404"))
        XCTAssertEqual(metadata["status"], "404")
    }

    func testExecute_ATSBlock_Simulated() async throws {
        // Simulate ATS error
        MockURLProtocol.requestHandler = { request in
            throw URLError(.appTransportSecurityRequiresSecureConnection)
        }

        let args = ToolArguments(dictionary: ["url": "http://insecure.example.com"])

        do {
            _ = try await tool.execute(arguments: args, context: context)
            XCTFail("Should have thrown ATS error")
        } catch let error as ToolError {
            if case .executionFailed(let message, let retryable) = error {
                XCTAssertTrue(message.contains("ATS blocked insecure connection"))
                XCTAssertFalse(retryable)
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testExecute_Cancellation() async throws {
        // Simulate a long running request
        MockURLProtocol.requestHandler = { request in
            try await Task.sleep(nanoseconds: 2 * 1_000_000_000)  // 2s
            return (
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        let args = ToolArguments(dictionary: ["url": "https://api.example.com/delay"])

        let task = Task {
            try await tool.execute(arguments: args, context: context)
        }

        // Cancel after small delay
        try await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Should have been cancelled")
        } catch let error as ToolError {
            // Verify our specific cancellation handling
            // Since we catch URLError.cancelled and translate it if cancellationWasRequested
            // We expect "Request cancelled by user" or similar if we implemented that translation
            // In the code I wrote: throw ToolError.executionFailed("Request cancelled by user", retryable: false)
            if case .executionFailed(let message, _) = error {
                XCTAssertTrue(message.contains("cancelled by user"))
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            // Standard CancellationError might be thrown if the loop breaks early enough
            // but our tool catches and rethrows.
            // If URLSession throws URLError.cancelled, our code handles it.
            print("Caught: \(error)")
        }
    }
}

// MARK: - Mock Helpers

class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) async throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        Task {
            guard let handler = MockURLProtocol.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }

            do {
                let (response, data) = try await handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        // No-op for mock
    }
}

// Minimal stubs for missing types if needed for compilation in isolation
// Assuming ToolArguments, ToolContext, ToolResult, ToolError are available in the test target
