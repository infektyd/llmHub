// Services/ToolTypes.swift
// Shared types for tool system

import Foundation

// MARK: - Tool Arguments

/// Type-safe wrapper for tool input arguments.
struct ToolArguments: Sendable {
    private let storage: [String: JSONValue]

    nonisolated init(_ dictionary: [String: Any]) {
        // Convert to JSONValue for type safety
        self.storage = dictionary.compactMapValues { JSONValue(from: $0) }
    }

    nonisolated init(_ jsonValues: [String: JSONValue]) {
        self.storage = jsonValues
    }

    nonisolated subscript(key: String) -> JSONValue? { storage[key] }

    nonisolated func string(_ key: String) -> String? {
        if case .string(let s) = storage[key] { return s }
        return nil
    }

    nonisolated func int(_ key: String) -> Int? {
        if case .number(let n) = storage[key] { return Int(n) }
        return nil
    }

    nonisolated func double(_ key: String) -> Double? {
        if case .number(let n) = storage[key] { return n }
        return nil
    }

    nonisolated func bool(_ key: String) -> Bool? {
        if case .bool(let b) = storage[key] { return b }
        return nil
    }

    nonisolated func array(_ key: String) -> [JSONValue]? {
        if case .array(let a) = storage[key] { return a }
        return nil
    }

    nonisolated func object(_ key: String) -> [String: JSONValue]? {
        if case .object(let o) = storage[key] { return o }
        return nil
    }

    /// Raw dictionary access (for legacy compatibility)
    nonisolated var rawDictionary: [String: Any] {
        storage.mapValues { $0.toAny() }
    }

    /// Legacy alias used by some tools.
    nonisolated var dictionary: [String: Any] { rawDictionary }
}

// MARK: - Tool Result

/// Structured result from tool execution.
struct ToolResult: Sendable {
    let success: Bool
    let output: String
    let metrics: ToolMetrics
    let metadata: [String: String]
    let truncated: Bool
    let continuationToken: String?

    nonisolated init(
        success: Bool,
        output: String,
        metrics: ToolMetrics = .empty,
        metadata: [String: String] = [:],
        truncated: Bool = false,
        continuationToken: String? = nil
    ) {
        self.success = success
        self.output = output
        self.metrics = metrics
        self.metadata = metadata
        self.truncated = truncated
        self.continuationToken = continuationToken
    }

    nonisolated static func success(
        _ output: String,
        metrics: ToolMetrics = .empty,
        metadata: [String: String] = [:],
        truncated: Bool = false
    ) -> ToolResult {
        ToolResult(
            success: true, output: output, metrics: metrics, metadata: metadata,
            truncated: truncated)
    }

    nonisolated static func failure(
        _ message: String,
        metrics: ToolMetrics = .empty,
        metadata: [String: String] = [:],
        errorClass: ToolErrorClass? = nil
    ) -> ToolResult {
        var m = metrics
        m.errorClass = errorClass
        return ToolResult(success: false, output: message, metrics: m, metadata: metadata)
    }
}

// MARK: - Tool Metrics (Observability)

/// Observability data captured during tool execution.
struct ToolMetrics: Sendable {
    var startTime: Date?
    var endTime: Date?
    nonisolated var durationMs: Int {
        guard let start = startTime, let end = endTime else { return 0 }
        return Int(end.timeIntervalSince(start) * 1000)
    }
    var bytesIn: Int?
    var bytesOut: Int?
    var cacheHit: Bool = false
    var retryCount: Int = 0
    var errorClass: ToolErrorClass?

    nonisolated static let empty = ToolMetrics()

    nonisolated mutating func markStart() { startTime = Date() }
    nonisolated mutating func markEnd() { endTime = Date() }
}

/// Classification of tool errors for diagnostics.
enum ToolErrorClass: String, Sendable, Codable {
    case timeout
    case networkUnreachable
    case dnsFailure
    case connectionRefused
    case sslError
    case httpError
    case parseError
    case validationError
    case authenticationError
    case authorizationDenied
    case resourceNotFound
    case rateLimited
    case quotaExceeded
    case sandboxViolation
    case internalError
    case unknown
}

// MARK: - Tool Error

/// Errors thrown during tool execution.
// MARK: - JSON Value

/// A type-safe wrapper for JSON values, useful for tool arguments and outputs.
enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Mismatched JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // Guard against non-finite values (NaN, Infinity) which are not valid JSON
            try container.encode(value.isFinite ? value : 0.0)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    // Convenience accessors
    nonisolated var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    nonisolated var doubleValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    nonisolated var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    nonisolated var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    nonisolated var dictionaryValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    nonisolated var description: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return "\(n)"
        case .bool(let b): return "\(b)"
        case .null: return "null"
        case .array(let a): return "\(a)"
        case .object(let o): return "\(o)"
        }
    }

    // Legacy support helpers
    nonisolated func toAny() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .number(let v): return v
        case .string(let v): return v
        case .array(let v): return v.map { $0.toAny() }
        case .object(let v): return v.mapValues { $0.toAny() }
        }
    }

    nonisolated init(from any: Any) {
        if any is NSNull {
            self = .null
        } else if let v = any as? Bool {
            self = .bool(v)
        } else if let v = any as? Double {
            self = .number(v)
        } else if let v = any as? Int {
            self = .number(Double(v))
        } else if let v = any as? String {
            self = .string(v)
        } else if let v = any as? [Any] {
            self = .array(v.map { JSONValue(from: $0) })
        } else if let v = any as? [String: Any] {
            self = .object(v.mapValues { JSONValue(from: $0) })
        } else {
            self = .string(String(describing: any))
        }
    }
}

// MARK: - Tool Error

/// Errors thrown during tool execution.
enum ToolError: Error, LocalizedError, Sendable {
    case invalidArguments(String)
    case executionFailed(String, retryable: Bool = false)
    case timeout(after: TimeInterval)
    case unauthorized(ToolCapability)
    case unavailable(reason: String)
    case sandboxViolation(String)

    // UI/Legacy Compatibility Cases
    case notFound(String)
    case notConfigured
    case platformNotSupported(String)

    nonisolated var errorDescription: String? {
        switch self {
        case .invalidArguments(let msg): return "Invalid arguments: \(msg)"
        case .executionFailed(let msg, _): return "Execution failed: \(msg)"
        case .timeout(let t): return "Timeout after \(t)s"
        case .unauthorized(let cap): return "Unauthorized: requires \(cap.rawValue)"
        case .unavailable(let reason): return "Tool unavailable: \(reason)"
        case .sandboxViolation(let msg): return "Sandbox violation: \(msg)"
        case .notFound(let msg): return "Tool not found: \(msg)"
        case .notConfigured: return "Tool not configured"
        case .platformNotSupported(let platform): return "Not supported on \(platform)"
        }
    }

    nonisolated var errorClass: ToolErrorClass {
        switch self {
        case .invalidArguments: return .validationError
        case .executionFailed: return .internalError
        case .timeout: return .timeout
        case .unauthorized: return .authorizationDenied
        case .unavailable, .notFound: return .resourceNotFound
        case .sandboxViolation: return .sandboxViolation
        case .notConfigured: return .authorizationDenied
        case .platformNotSupported: return .resourceNotFound
        }
    }
}

// MARK: - Schema Types

/// JSON Schema for tool parameters.
struct ToolParametersSchema: Sendable {
    var type: String = "object"
    let properties: [String: ToolProperty]
    let required: [String]

    nonisolated init(properties: [String: ToolProperty], required: [String] = []) {
        self.properties = properties
        self.required = required
    }
}

/// Single property in a tool schema.
final class ToolProperty: @unchecked Sendable {
    let type: JSONSchemaType
    let description: String
    let enumValues: [String]?
    let items: ToolProperty?  // For arrays

    nonisolated init(
        type: JSONSchemaType, description: String, enumValues: [String]? = nil,
        items: ToolProperty? = nil
    ) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self.items = items
    }

    nonisolated deinit {}
}

/// JSON Schema type identifiers.
enum JSONSchemaType: String, Sendable, Codable {
    case string, number, integer, boolean, array, object
}  // MARK: - Tool Capabilities

/// Capabilities a tool may require to execute.
enum ToolCapability: String, Sendable, Codable, CaseIterable {
    case fileSystem  // Read/write local files
    case networkIO  // HTTP requests, sockets
    case shellExecution  // Run shell commands
    case codeExecution  // Execute user code (XPC sandbox)
    case browserControl  // Automate browser
    case systemEvents  // macOS automation

    // Legacy/feature-specific capabilities still referenced across the codebase.
    case webAccess
    case fileRead
    case fileWrite
    case dbAccess
    case notifications
    case scheduleTasks
    case imageGeneration
    case workspace
}

// MARK: - Tool Availability

/// Result of checking tool availability in an environment.
enum ToolAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: String)
    case requiresAuthorization(capability: ToolCapability)

    /// Legacy alias used by some tools.
    nonisolated var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    /// Legacy alias used by UI/tool selection code.
    var isSupported: Bool { isAvailable }

    /// Legacy alias used by UI to display why unavailable.
    var details: String? {
        switch self {
        case .available:
            return nil
        case .unavailable(let reason):
            return reason
        case .requiresAuthorization(let capability):
            return "Requires \(capability.rawValue)"
        }
    }
}

// MARK: - Tool Permission Level

/// Authorization requirement for tool execution.
enum ToolPermissionLevel: String, Sendable, Codable {
    case safe  // No confirmation needed (calculator, etc.)
    case standard  // Legacy middle tier
    case sensitive  // Requires user consent (web search, file read)
    case dangerous  // Explicit confirmation per execution (shell, file write)
}

// MARK: - Tool Weight

/// Execution weight for concurrency management.
enum ToolWeight: String, Sendable, Codable {
    case fast  // Execute immediately (calculator, simple lookups)
    case standard  // Legacy default tier
    case heavy  // May be queued/rate-limited (browser, shell, API calls)
}
