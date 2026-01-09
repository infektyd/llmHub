// Services/ToolExecutor.swift
// Concurrent tool execution engine

import Foundation
import OSLog

/// Result of tool execution with correlation ID.
struct ToolCallResult: Sendable, Identifiable {
    let id: String
    let toolName: String
    let result: ToolResult

    var success: Bool { result.success }
    var output: String { result.output }
    var metrics: ToolMetrics { result.metrics }
}

/// Concurrent tool execution engine.
actor ToolExecutor {
    private let registry: ToolRegistry
    private let environment: ToolEnvironment
    private var heavySlots: Int
    private let maxHeavySlots: Int
    private let logger = Logger(subsystem: "com.llmhub", category: "ToolExecutor")

    init(registry: ToolRegistry, environment: ToolEnvironment, maxConcurrentHeavy: Int = 3) {
        self.registry = registry
        self.environment = environment
        self.maxHeavySlots = maxConcurrentHeavy
        self.heavySlots = maxConcurrentHeavy
    }

    /// Execute multiple tools concurrently, streaming results.
    func execute(calls: [ToolCall], context: ToolContext) -> AsyncStream<ToolCallResult> {
        AsyncStream { continuation in
            Task {
                await withTaskGroup(of: ToolCallResult.self) { group in
                    for call in calls {
                        group.addTask {
                            await self.executeSingle(call, context: context)
                        }
                    }
                    for await result in group {
                        continuation.yield(result)
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Execute a single tool call.
    func executeSingle(_ call: ToolCall, context: ToolContext) async -> ToolCallResult {
        var metrics = ToolMetrics()
        metrics.markStart()

        let rawArguments: ToolArguments
        do {
            rawArguments = try parseArguments(from: call.input)
        } catch {
            metrics.markEnd()
            metrics.errorClass = .validationError
            let payload = toolCallRejectedJSON(
                id: call.id,
                toolName: call.name,
                reason: "invalid_arguments",
                message: "Invalid tool arguments (expected a JSON object)."
            )
            return ToolCallResult(
                id: call.id,
                toolName: call.name,
                result: .failure(
                    payload,
                    metrics: metrics,
                    errorClass: .validationError
                )
            )
        }

        // Find tool (lookup + availability check)
        guard let tool = await registry.tool(named: call.name) else {
            metrics.markEnd()
            metrics.errorClass = .resourceNotFound
            let payload = toolCallRejectedJSON(
                id: call.id,
                toolName: call.name,
                reason: "unknown_tool",
                message: "Tool not found."
            )
            return ToolCallResult(
                id: call.id,
                toolName: call.name,
                result: .failure(
                    payload,
                    metrics: metrics,
                    errorClass: .resourceNotFound
                )
            )
        }

        // Normalize common argument-key variations before validation/execution.
        // Rationale: Different providers/models sometimes emit camelCase keys even when schema uses snake_case.
        // Example: read_file might be called with {"filePath":..., "startLine":...}.
        let arguments = normalizeArguments(rawArguments, for: tool.parameters)

        guard tool.availability(in: environment).isAvailable else {
            metrics.markEnd()
            metrics.errorClass = .resourceNotFound
            return ToolCallResult(
                id: call.id,
                toolName: call.name,
                result: .failure(
                    "Tool not available in current environment: \(call.name)",
                    metrics: metrics,
                    errorClass: .resourceNotFound
                )
            )
        }

        // Validate tool-call payload against the tool's declared schema.
        // Rationale: Model-produced tool calls can be syntactically valid JSON but still violate schema.
        let schemaErrors = validate(arguments: arguments, schema: tool.parameters)
        if !schemaErrors.isEmpty {
            metrics.markEnd()
            metrics.errorClass = .validationError
            let payload = toolCallRejectedJSON(
                id: call.id,
                toolName: call.name,
                reason: "schema_validation_failed",
                message: "Tool arguments did not match schema.",
                errors: schemaErrors
            )
            return ToolCallResult(
                id: call.id,
                toolName: call.name,
                result: .failure(payload, metrics: metrics, errorClass: .validationError)
            )
        }

        // Enforce user authorization if configured.
        // SECURITY: Authorization context is REQUIRED. If missing, fail immediately.
        guard let auth = context.authorization else {
            metrics.markEnd()
            metrics.errorClass = .authorizationDenied
            logger.error("🔴 SECURITY: No authorization context provided for tool '\(call.name)' in call ID \(call.id)")
            return ToolCallResult(
                id: call.id,
                toolName: call.name,
                result: .failure(
                    "System configuration error: Authorization context missing",
                    metrics: metrics,
                    errorClass: .authorizationDenied
                )
            )
        }
        
        // Check authorization status
        // SECURITY: .notDetermined is treated as .denied (secure by default)
        // Use conversation-scoped authorization via context.sessionID
        let status = await auth.checkAccess(for: tool.name, conversationID: context.sessionID)
        if status != .authorized {
            metrics.markEnd()
            metrics.errorClass = .authorizationDenied
            let statusName = status == .denied ? "denied" : "not determined"
            logger.warning("🔒 Tool '\(call.name)' blocked for call ID \(call.id): status=\(statusName)")
            return ToolCallResult(
                id: call.id,
                toolName: call.name,
                result: .failure(
                    "Unauthorized: Tool '\(call.name)' requires user permission",
                    metrics: metrics,
                    errorClass: .authorizationDenied
                )
            )
        }

        let effectiveWeight = tool.weight

        // Check cache
        if tool.isCacheable {
            let cacheKey = generateCacheKey(call)
            if let cached = await context.session.getCached(key: cacheKey) {
                var cachedMetrics = cached.metrics
                cachedMetrics.cacheHit = true
                return ToolCallResult(
                    id: call.id,
                    toolName: call.name,
                    result: ToolResult(
                        success: cached.success,
                        output: cached.output,
                        metrics: cachedMetrics,
                        metadata: cached.metadata,
                        truncated: cached.truncated
                    )
                )
            }
        }

        // Acquire heavy slot if needed
        if effectiveWeight == .heavy {
            await acquireHeavySlot()
        }

        defer {
            if effectiveWeight == .heavy {
                releaseHeavySlot()
            }
        }

        // Execute with orchestration-level timeout (STEP 2)
        // Hard deadline: 300s for all tools, can be overridden per-tool later
        let timeoutSeconds = 300
        
        do {
            let result = try await withTimeout(seconds: timeoutSeconds) {
                try await tool.execute(arguments: arguments, context: context)
            }
            metrics.markEnd()

            let finalResult = ToolResult(
                success: result.success,
                output: result.output,
                metrics: ToolMetrics(
                    startTime: metrics.startTime,
                    endTime: metrics.endTime,
                    bytesIn: result.metrics.bytesIn,
                    bytesOut: result.metrics.bytesOut,
                    cacheHit: false,
                    retryCount: result.metrics.retryCount,
                    errorClass: result.metrics.errorClass
                ),
                metadata: result.metadata,
                truncated: result.truncated,
                continuationToken: result.continuationToken
            )

            // Cache if applicable
            if tool.isCacheable {
                await context.session.cache(finalResult, key: generateCacheKey(call))
            }

            if let fileSummary = summarizeFileAccess(metadata: finalResult.metadata) {
                logger.info("✅ \(call.name) completed in \(metrics.durationMs)ms (\(fileSummary))")
            } else {
                logger.info("✅ \(call.name) completed in \(metrics.durationMs)ms")
            }
            return ToolCallResult(id: call.id, toolName: call.name, result: finalResult)

        } catch let error as ToolError {
            metrics.markEnd()
            
            // Handle timeout specifically
            if case .timeout(let duration) = error {
                metrics.errorClass = .timeout
                logger.error("⏱️ \(call.name) timed out after \(duration)s")
                let timeoutMessage = "Tool execution timed out after \(duration) seconds. The operation was cancelled."
                return ToolCallResult(
                    id: call.id,
                    toolName: call.name,
                    result: .failure(timeoutMessage, metrics: metrics, errorClass: .timeout)
                )
            }
            
            metrics.errorClass = error.errorClass
            logger.error("❌ \(call.name) failed: \(error.localizedDescription)")
            return ToolCallResult(
                id: call.id,
                toolName: call.name,
                result: .failure(
                    error.localizedDescription, metrics: metrics, errorClass: error.errorClass)
            )

        } catch {
            metrics.markEnd()
            metrics.errorClass = .unknown
            logger.error("❌ \(call.name) failed: \(error.localizedDescription)")
            return ToolCallResult(
                id: call.id,
                toolName: call.name,
                result: .failure(error.localizedDescription, metrics: metrics, errorClass: .unknown)
            )
        }
    }

    private nonisolated func summarizeFileAccess(metadata: [String: String]) -> String? {
        // Keep logs compact and user-auditable.
        if let resolved = metadata["resolvedPath"] {
            return "path=\(resolved)"
        }
        if let path = metadata["path"] {
            return "path=\(path)"
        }
        return nil
    }

    private func generateCacheKey(_ call: ToolCall) -> String {
        return "\(call.name):\(call.input.hashValue)"
    }

    private func parseArguments(from input: String) throws -> ToolArguments {
        guard let data = input.data(using: .utf8) else {
            throw ToolError.invalidArguments("Input is not valid UTF-8")
        }
        let any = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = any as? [String: Any] else {
            throw ToolError.invalidArguments("Expected a JSON object")
        }
        return ToolArguments(dict)
    }

    private func normalizeArguments(
        _ arguments: ToolArguments,
        for schema: ToolParametersSchema
    ) -> ToolArguments {
        var values = arguments.jsonValuesByKey

        // 1) camelCase -> snake_case when the schema expects snake_case.
        for (key, value) in values {
            let snake = Self.camelToSnake(key)
            guard snake != key else { continue }
            guard values[snake] == nil else { continue }
            guard schema.properties[snake] != nil else { continue }
            values[snake] = value
        }

        // 2) Common aliases: filePath -> path, file_path -> path (used by read_file and file tools).
        if schema.properties["path"] != nil, values["path"] == nil {
            if let v = values["filePath"] ?? values["file_path"] {
                values["path"] = v
            }
        }

        return ToolArguments(values)
    }

    private static func camelToSnake(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var result: [Character] = []
        result.reserveCapacity(s.count + 4)

        var previousWasUpper = false
        for ch in s {
            if ch.isUppercase {
                if !result.isEmpty && !previousWasUpper {
                    result.append("_")
                }
                result.append(Character(ch.lowercased()))
                previousWasUpper = true
            } else {
                result.append(ch)
                previousWasUpper = false
            }
        }
        return String(result)
    }

    // MARK: - Tool Call Validation / Rejection

    private struct ToolCallRejected: Encodable {
        let type: String = "tool_call_rejected"
        let toolCallId: String
        let toolName: String
        let reason: String
        let message: String
        let errors: [String]?
    }

    private func toolCallRejectedJSON(
        id: String,
        toolName: String,
        reason: String,
        message: String,
        errors: [String]? = nil
    ) -> String {
        let payload = ToolCallRejected(
            toolCallId: id,
            toolName: toolName,
            reason: reason,
            message: message,
            errors: errors
        )
        let encoder = JSONEncoder()
        if #available(iOS 11.0, macOS 10.13, *) {
            encoder.outputFormatting = [.sortedKeys]
        }
        if let data = try? encoder.encode(payload), let text = String(data: data, encoding: .utf8) {
            return text
        }
        // Last-resort fallback: keep the string JSON-like even if encoding fails.
        return #"{"type":"tool_call_rejected","toolCallId":"\#(id)","toolName":"\#(toolName)","reason":"\#(reason)","message":"\#(message)"}"#
    }

    private func validate(arguments: ToolArguments, schema: ToolParametersSchema) -> [String] {
        var errors: [String] = []
        let values = arguments.jsonValuesByKey

        for requiredKey in schema.required {
            if values[requiredKey] == nil {
                errors.append("Missing required property '\(requiredKey)'.")
            }
        }

        for (key, property) in schema.properties {
            guard let value = values[key] else { continue }

            if !matches(value: value, schemaType: property.type) {
                errors.append("Property '\(key)' expected type \(property.type.rawValue).")
                continue
            }

            if let allowed = property.enumValues,
                case .string(let s) = value,
                !allowed.contains(s)
            {
                errors.append(
                    "Property '\(key)' must be one of [\(allowed.joined(separator: ", "))]."
                )
            }

            if property.type == .array, let items = property.items, case .array(let arr) = value {
                for (idx, element) in arr.enumerated() {
                    if !matches(value: element, schemaType: items.type) {
                        errors.append(
                            "Property '\(key)[\(idx)]' expected type \(items.type.rawValue)."
                        )
                    }
                }
            }
        }

        return errors
    }

    private func matches(value: JSONValue, schemaType: JSONSchemaType) -> Bool {
        switch (schemaType, value) {
        case (.string, .string): return true
        case (.number, .number): return true
        case (.number, .string(let s)):
            return Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
        case (.integer, .number(let n)): return n.rounded() == n
        case (.integer, .string(let s)):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if Int(trimmed) != nil { return true }
            if let d = Double(trimmed), d.rounded() == d { return true }
            return false
        case (.boolean, .bool): return true
        case (.array, .array): return true
        case (.object, .object): return true
        default: return false
        }
    }

    private func acquireHeavySlot() async {
        while heavySlots <= 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }
        heavySlots -= 1
    }

    private func releaseHeavySlot() {
        heavySlots = min(heavySlots + 1, maxHeavySlots)
    }

    // MARK: - Timeout Helper

    /// Races an async operation against a timeout.
    /// - Throws: ToolError.timeout if timeout is reached, or the operation's error.
    private func withTimeout<T: Sendable>(
        seconds: Int,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                throw ToolError.timeout(after: TimeInterval(seconds))
            }

            guard let result = try await group.next() else {
                group.cancelAll()
                throw ToolError.executionFailed(
                    "Task group completed without result", retryable: true)
            }

            group.cancelAll()
            return result
        }
    }
}
