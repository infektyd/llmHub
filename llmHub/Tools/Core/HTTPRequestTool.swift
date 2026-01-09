//
//  HTTPRequestTool.swift
//  llmHub
//
//  Direct HTTP request tool for API interactions
//

import Foundation
import _Concurrency
import os
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
                )
            ],
            required: ["url"]
        )
    }

    let permissionLevel: ToolPermissionLevel = .sensitive
    let requiredCapabilities: [ToolCapability] = [.networkIO]
    let weight: ToolWeight = .heavy
    let isCacheable = false

    private let maxBodyPreview = 64_000
    private let baseSessionConfiguration: URLSessionConfiguration

    init(sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        // Copy to prevent external mutation and to avoid any implicit reliance on URLSession.shared.
        self.baseSessionConfiguration = (sessionConfiguration.copy() as? URLSessionConfiguration)
            ?? .ephemeral
    }

    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws
        -> ToolResult {
        let startTime = Date()

        // STEP 0: Log execution context for debugging
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let processName = ProcessInfo.processInfo.processName
        let pid = ProcessInfo.processInfo.processIdentifier
        context.logger.info(
            "🌐 http_request executing in: \(bundleID) (process: \(processName), PID: \(pid))")

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
                    let pass = authDict["password"]?.stringValue {
                    let creds = Data("\(user):\(pass)".utf8).base64EncodedString()
                    resolvedHeaders["Authorization"] = "Basic \(creds)"
                }
            }
        }

        // Settings
        let timeout = max(1, min(arguments.int("timeout") ?? 30, 120))
        let allowRedirects = arguments.bool("follow_redirects") ?? true
        let retries = max(0, min(arguments.int("retry") ?? 0, 3))
        let responseFormat = arguments.string("response_format")?.lowercased() ?? "json"

        // Redact sensitive headers by KEY (Authorization, Cookie, etc)
        let sensitiveKeys: Set<String> = [
            "authorization", "proxy-authorization", "cookie", "set-cookie", "x-api-key"
        ]
        _ = resolvedHeaders.mapValues { value in
            // We can return "[REDACTED]" but mapValues gives us just the value.
            // We need to check the key. Since mapValues doesn't give key, we do it differently.
            return value
        }

        var safeHeadersForLog = resolvedHeaders
        for (key, _) in resolvedHeaders where sensitiveKeys.contains(key.lowercased()) {
            safeHeadersForLog[key] = "[REDACTED]"
        }

        context.logger.info(
            "📤 Request: \(method) \(urlString), timeout: \(timeout)s, headers: \(safeHeadersForLog)"
        )

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

        // Execution Loop with Retry and Cancellation Support
        var attempt = 0
        var lastError: Error?
        let cancellationWasRequested = OSAllocatedUnfairLock(initialState: false)

        // Create a dedicated URLSession for this tool execution.
        // Cancellation must only affect requests within this tool call.
        let sessionConfig = (baseSessionConfiguration.copy() as? URLSessionConfiguration)
            ?? .ephemeral
        sessionConfig.timeoutIntervalForRequest = TimeInterval(timeout)
        sessionConfig.timeoutIntervalForResource = TimeInterval(timeout)

        let dedicatedSession = URLSession(
            configuration: sessionConfig,
            delegate: allowRedirects ? nil : RedirectBlocker(),
            delegateQueue: nil
        )
        defer {
            dedicatedSession.finishTasksAndInvalidate()
        }

        while attempt <= retries {
            do {
                let (data, response) = try await withTaskCancellationHandler {
                    try await dedicatedSession.data(for: request)
                } onCancel: {
                    cancellationWasRequested.withLock { $0 = true }
                    // Invalidate and cancel ONLY this dedicated session.
                    dedicatedSession.invalidateAndCancel()
                }

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
                    .compactMap { (key: AnyHashable, value: Any) -> String? in
                        guard let k = key as? String else { return nil }
                        return "\(k): \(value)"
                    }
                    .sorted()
                    .joined(separator: "\n")

                var output = "\(statusLine)\n\(headerSummary)\n\n\(bodyText)"
                if truncated {
                    output.append("\n\n[response truncated to \(maxBodyPreview) bytes]")
                }

                let duration = Date().timeIntervalSince(startTime)
                let elapsedMs = Int(duration * 1000)

                context.logger.info(
                    "📥 Response: \(httpResponse.statusCode), bytes: \(data.count), time: \(elapsedMs)ms"
                )

                return ToolResult.success(
                    output,
                    metadata: [
                        "status": "\(httpResponse.statusCode)",
                        "url": httpResponse.url?.absoluteString ?? urlString,
                        "bytesReceived": "\(data.count)",
                        "elapsedMs": "\(elapsedMs)",
                        "cancellationRequested": "\(cancellationWasRequested.withLock { $0 })",
                        "process": "\(bundleID)"
                    ],
                    truncated: truncated
                )

            } catch let error as URLError {
                lastError = error

                if error.code == .cancelled {
                    // Check if it was our explicit cancellation
                    if cancellationWasRequested.withLock({ $0 }) {
                        throw ToolError.executionFailed(
                            "Request cancelled by user", retryable: false)
                    }
                }

                // ATS Helper
                if error.code == .appTransportSecurityRequiresSecureConnection {
                    let msg =
                        "⚠️ ATS blocked insecure connection; use https:// or run: nscurl --ats-diagnostics \(urlString)"
                    context.logger.error("\(msg)")
                    // Fail immediately for ATS, don't retry
                    throw ToolError.executionFailed(msg, retryable: false)
                }

                attempt += 1

                let errorDomain = (error as NSError).domain
                let errorCode = (error as NSError).code
                context.logger.error(
                    "❌ URLError: domain=\(errorDomain), code=\(errorCode), desc=\(error.localizedDescription)"
                )

                if attempt > retries { break }
                let backoff = UInt64(min(pow(2.0, Double(attempt)), 6.0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: backoff)

            } catch {
                lastError = error

                if error is CancellationError,
                    cancellationWasRequested.withLock({ $0 }) {
                    throw ToolError.executionFailed(
                        "Request cancelled by user", retryable: false)
                }

                attempt += 1
                context.logger.error("❌ Error: \(type(of: error)) - \(error.localizedDescription)")

                if attempt > retries { break }
                let backoff = UInt64(min(pow(2.0, Double(attempt)), 6.0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: backoff)
            }
        }

        // Failure Result
        let duration = Date().timeIntervalSince(startTime)
        let elapsedMs = Int(duration * 1000)

        let errorDetail: String
        if let urlError = lastError as? URLError {
            errorDetail = """
                HTTP request failed after \(retries + 1) attempt(s). Time: \(elapsedMs)ms
                Error: \(urlError.localizedDescription)
                Domain: \(urlError.code.rawValue) (\(urlError.code))
                URL: \(urlError.failingURL?.absoluteString ?? urlString)
                """
        } else {
            errorDetail = """
                HTTP request failed after \(retries + 1) attempt(s). Time: \(elapsedMs)ms
                Error: \(lastError?.localizedDescription ?? "Unknown error")
                """
        }

        throw ToolError.executionFailed(errorDetail, retryable: retries > 0)
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

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool

    init(_ initialValue: Bool) {
        self._value = initialValue
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func setTrue() {
        lock.lock()
        _value = true
        lock.unlock()
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
            let text = String(data: pretty, encoding: .utf8) {
            let truncated = pretty.count > 64_000
            return (truncated ? String(text.prefix(64_000)) : text, truncated)
        }
    }

    let text = String(data: data, encoding: .utf8) ?? data.prefix(8_192).base64EncodedString()
    let truncated = text.utf8.count > 64_000
    return (truncated ? String(text.prefix(64_000)) : text, truncated)
}

// JSONValue helper extension removed (moved to ToolTypes.swift)
