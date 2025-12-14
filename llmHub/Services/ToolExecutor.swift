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

        let arguments: ToolArguments
        do {
            arguments = try parseArguments(from: call.input)
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
        if let auth = context.authorization {
            let status = await auth.checkAccess(for: tool.name)
            if status != .authorized {
                metrics.markEnd()
                metrics.errorClass = .authorizationDenied
                return ToolCallResult(
                    id: call.id,
                    toolName: call.name,
                    result: .failure(
                        "Unauthorized tool: \(call.name)",
                        metrics: metrics,
                        errorClass: .authorizationDenied
                    )
                )
            }
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

        // Execute
        do {
            let result = try await tool.execute(arguments: arguments, context: context)
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

            logger.info("✅ \(call.name) completed in \(metrics.durationMs)ms")
            return ToolCallResult(id: call.id, toolName: call.name, result: finalResult)

        } catch let error as ToolError {
            metrics.markEnd()
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
        case (.integer, .number(let n)): return n.rounded() == n
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
}
