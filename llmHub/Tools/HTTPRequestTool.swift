//
//  HTTPRequestTool.swift
//  llmHub
//
//  Direct HTTP request tool for API interactions
//

import Foundation
import OSLog

/// HTTP Request Tool conforming to the unified Tool protocol.
nonisolated struct HTTPRequestTool: Tool {
    let name = "http_request"
    let description = """
        Make HTTP requests to REST APIs and web services. \
        Supports GET, POST, PUT, DELETE, PATCH methods with custom headers, auth, redirects, and retries. \
        Use this tool when you need to interact with APIs directly. Prefer web_search for public pages.
        """

    nonisolated var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "url": ToolProperty(type: .string, description: "The URL to request"),
                "method": ToolProperty(
                    type: .string,
                    description: "HTTP method (default: GET)",
                    enumValues: ["GET", "POST", "PUT", "DELETE", "PATCH"]
                ),
                "headers": ToolProperty(
                    type: .object, description: "Optional HTTP headers as key-value pairs"),
                "body": ToolProperty(
                    type: .string, description: "Optional request body (for POST, PUT, PATCH)"),
                "auth": ToolProperty(
                    type: .object,
                    description:
                        "Authentication info. bearer uses token; basic uses username/password."
                ),
                "timeout": ToolProperty(
                    type: .integer, description: "Timeout in seconds (default: 30, max: 120)"),
                "follow_redirects": ToolProperty(
                    type: .boolean, description: "Whether to follow redirects (default: true)"),
                "retry": ToolProperty(
                    type: .integer,
                    description: "Retry count with exponential backoff (default: 0, max: 3)"),
                "response_format": ToolProperty(
                    type: .string,
                    description: "Preferred response format (default: json then text)",
                    enumValues: ["text", "json", "bytes"]
                ),
            ],
            required: ["url"]
        )
    }

    let permissionLevel: ToolPermissionLevel = .sensitive
    let requiredCapabilities: [ToolCapability] = [.networkIO]
    let weight: ToolWeight = .heavy
    let isCacheable = false

    private let maxBodyPreview = 64_000
    private let urlSession: URLSession

    init(session: URLSession = .shared) {
        self.urlSession = session
    }

    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        guard let urlString = arguments.string("url"), let url = URL(string: urlString) else {
            throw ToolError.invalidArguments("url is required and must be valid")
        }

        let method = arguments.string("method")?.uppercased() ?? "GET"
        let headers = arguments.object("headers")?.compactMapValues { $0.stringValue } ?? [:]
        let bodyString = arguments.string("body")

        // Auth handling
        var resolvedHeaders = headers
        if let authDict = arguments.object("auth") {
            if let type = authDict["type"]?.stringValue?.lowercased() {
                if type == "bearer", let token = authDict["token"]?.stringValue {
                    resolvedHeaders["Authorization"] = "Bearer \(token)"
                } else if type == "basic",
                    let user = authDict["username"]?.stringValue,
                    let pass = authDict["password"]?.stringValue
                {
                    let creds = "\(user):\(pass)".data(using: .utf8)?.base64EncodedString() ?? ""
                    resolvedHeaders["Authorization"] = "Basic \(creds)"
                }
            }
        }

        // Settings
        let timeout = max(1, min(arguments.int("timeout") ?? 30, 120))
        let allowRedirects = arguments.bool("follow_redirects") ?? true
        let retries = max(0, min(arguments.int("retry") ?? 0, 3))
        let responseFormat = arguments.string("response_format")?.lowercased() ?? "json"

        // Build Request
        var request = URLRequest(url: url, timeoutInterval: TimeInterval(timeout))
        request.httpMethod = method
        request.allHTTPHeaderFields = resolvedHeaders
        if let body = bodyString {
            request.httpBody = body.data(using: .utf8)
            if resolvedHeaders["Content-Type"] == nil {
                request.setValue(
                    "application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            }
        }

        // Session Configuration
        let sessionConfig = urlSession.configuration
        let httpSession = URLSession(
            configuration: sessionConfig,
            delegate: allowRedirects ? nil : RedirectBlocker(),
            delegateQueue: nil
        )

        // Execution Loop with Retry
        var attempt = 0
        var lastError: Error?

        while attempt <= retries {
            do {
                let (data, response) = try await httpSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                let (bodyText, truncated) = formatBody(
                    data: data,
                    format: responseFormat,
                    contentType: httpResponse.value(forHTTPHeaderField: "Content-Type")
                )

                let statusLine = "HTTP \(httpResponse.statusCode)"
                let headerSummary = httpResponse.allHeaderFields
                    .compactMap { key, value in
                        guard let k = key as? String else { return nil }
                        return "\(k): \(value)"
                    }
                    .sorted()
                    .joined(separator: "\n")

                var output = "\(statusLine)\n\(headerSummary)\n\n\(bodyText)"
                if truncated {
                    output.append("\n\n[response truncated to \(maxBodyPreview) bytes]")
                }

                context.logger.info(
                    "HTTP \(method) \(url.absoluteString) -> \(httpResponse.statusCode)")

                return ToolResult.success(
                    output,
                    metadata: [
                        "status": "\(httpResponse.statusCode)",
                        "url": httpResponse.url?.absoluteString ?? urlString,
                    ],
                    truncated: truncated
                )

            } catch {
                lastError = error
                attempt += 1
                if attempt > retries { break }
                let backoff = UInt64(min(pow(2.0, Double(attempt)), 6.0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: backoff)
            }
        }

        throw ToolError.executionFailed(
            "HTTP request failed: \(lastError?.localizedDescription ?? "Unknown error")",
            retryable: retries > 0
        )
    }
}

// MARK: - Helpers

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

private nonisolated func formatBody(data: Data, format: String, contentType: String?) -> (
    String, Bool
) {
    if format == "bytes" {
        let base64 = data.base64EncodedString()
        let truncated = base64.count > 64_000
        return (truncated ? String(base64.prefix(64_000)) : base64, truncated)
    }

    if format == "json" || contentType?.contains("json") == true {
        if let jsonObj = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: jsonObj, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: pretty, encoding: .utf8)
        {
            let truncated = pretty.count > 64_000
            return (truncated ? String(text.prefix(64_000)) : text, truncated)
        }
    }

    let text = String(data: data, encoding: .utf8) ?? data.prefix(8_192).base64EncodedString()
    let truncated = text.utf8.count > 64_000
    return (truncated ? String(text.prefix(64_000)) : text, truncated)
}

// JSONValue helper extension removed (moved to ToolTypes.swift)
