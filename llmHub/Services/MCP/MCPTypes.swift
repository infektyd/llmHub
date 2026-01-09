//
//  MCPTypes.swift
//  llmHub
//
//  Data types for Model Context Protocol (MCP)
//

import Foundation

// MARK: - MCP Data Types

/// Configuration for an MCP server connection.
struct MCPServerConfig: Codable, Identifiable, Sendable {
    /// Unique identifier for the server configuration.
    var id: UUID = UUID()
    /// Display name of the server.
    let name: String
    /// Executable command to launch the server.
    let command: String
    /// Arguments to pass to the executable.
    let args: [String]
    /// Environment variables for the server process.
    let env: [String: String]?
    /// Whether this server is currently enabled.
    var isEnabled: Bool = true
}

/// Empty params struct for requests that don't need params.
struct EmptyParams: Encodable, Sendable {
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

/// Parameters for calling an MCP tool.
struct MCPToolCallParams: Encodable, Sendable {
    /// Name of the tool to call.
    let name: String
    /// Arguments for the tool.
    let arguments: MCPJSONValue

    enum CodingKeys: String, CodingKey {
        case name, arguments
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(arguments, forKey: .arguments)
    }
}

/// Parameters for reading an MCP resource.
struct MCPResourceReadParams: Encodable, Sendable {
    /// The URI of the resource.
    let uri: String

    enum CodingKeys: String, CodingKey {
        case uri
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uri, forKey: .uri)
    }
}

// JSON value wrapper for MCP API (handles Any -> Encodable conversion)
/// A wrapper enum to handle untyped JSON values in a strongly typed way for Encodable conformance in MCP.
enum MCPJSONValue: Encodable, Sendable {
    /// Null value.
    case null
    /// Boolean value.
    case bool(Bool)
    /// Integer value.
    case int(Int)
    /// Double value.
    case double(Double)
    /// String value.
    case string(String)
    /// Array of values.
    case array([MCPJSONValue])
    /// Object (dictionary) of values.
    case object([String: MCPJSONValue])

    /// Converts an `Any` value to `MCPJSONValue`.
    nonisolated static func from(_ value: Any) -> MCPJSONValue {
        switch value {
        case is NSNull:
            return .null
        case let b as Bool:
            return .bool(b)
        case let i as Int:
            return .int(i)
        case let d as Double:
            return .double(d)
        case let s as String:
            return .string(s)
        case let arr as [Any]:
            return .array(arr.map { from($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { from($0) })
        default:
            return .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let b):
            try container.encode(b)
        case .int(let i):
            try container.encode(i)
        case .double(let d):
            // Guard against non-finite values (NaN, Infinity) which are not valid JSON
            try container.encode(d.isFinite ? d : 0.0)
        case .string(let s):
            try container.encode(s)
        case .array(let arr):
            try container.encode(arr)
        case .object(let dict):
            try container.encode(dict)
        }
    }
}

/// A generic JSON-RPC request.
struct MCPRequest<T: Encodable & Sendable>: Encodable, Sendable {
    /// The JSON-RPC version (must be "2.0").
    let jsonrpc: String
    /// The request ID.
    let id: Int
    /// The method name.
    let method: String
    /// The request parameters.
    let params: T

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        try container.encode(params, forKey: .params)
    }
}

/// A generic JSON-RPC notification.
struct MCPNotification<T: Encodable & Sendable>: Encodable, Sendable {
    /// The JSON-RPC version (must be "2.0").
    let jsonrpc: String
    /// The notification method name.
    let method: String
    /// The notification parameters.
    let params: T

    enum CodingKeys: String, CodingKey {
        case jsonrpc, method, params
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(method, forKey: .method)
        try container.encode(params, forKey: .params)
    }
}

/// A generic JSON-RPC response.
struct MCPResponse: Decodable, Sendable {
    /// The JSON-RPC version.
    let jsonrpc: String
    /// The request ID this response corresponds to.
    let id: Int?
    /// The result payload (if successful).
    let result: AnySendable?
    /// The error payload (if failed).
    let error: MCPErrorInfo?

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        error = try container.decodeIfPresent(MCPErrorInfo.self, forKey: .error)

        // Decode result as AnySendable
        if let dict = try? container.decode([String: AnyCodable].self, forKey: .result) {
            result = AnySendable(dict.mapValues { $0.value })
        } else if let array = try? container.decode([AnyCodable].self, forKey: .result) {
            result = AnySendable(array.map { $0.value })
        } else {
            result = nil
        }
    }
}

/// Thread-safe wrapper for Any values.
struct AnySendable: @unchecked Sendable {
    nonisolated(unsafe) let value: Any

    nonisolated init(_ value: Any) {
        self.value = value
    }
}

/// Information about an error in a JSON-RPC response.
struct MCPErrorInfo: Decodable, Sendable {
    /// The error code.
    let code: Int
    /// The error message.
    let message: String
    /// Additional error data.
    let data: String?
}

/// Parameters for the initialize request.
struct MCPInitializeParams: Encodable, Sendable {
    /// The protocol version requested.
    let protocolVersion: String
    /// The capabilities of the client.
    let capabilities: MCPClientCapabilities
    /// Information about the client application.
    let clientInfo: MCPClientInfo

    enum CodingKeys: String, CodingKey {
        case protocolVersion, capabilities, clientInfo
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(clientInfo, forKey: .clientInfo)
    }
}

/// Capabilities of the MCP client.
struct MCPClientCapabilities: Encodable, Sendable {

    nonisolated func encode(to encoder: Encoder) throws {
        var _ = encoder.container(keyedBy: CodingKeys.self)
    }
    enum CodingKeys: String, CodingKey {
        case none  // Dummy case to satisfy CodingKey requirement if needed, or just use empty container
    }
}

/// Information about the client application.
struct MCPClientInfo: Encodable, Sendable {
    /// The name of the client application.
    let name: String
    /// The version of the client application.
    let version: String

    enum CodingKeys: String, CodingKey {
        case name, version
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(version, forKey: .version)
    }
}

/// Result of the initialize request.
struct MCPInitializeResult: Decodable, Sendable {
    /// The negotiated protocol version.
    let protocolVersion: String?
    /// The capabilities of the server.
    let capabilities: MCPServerCapabilities?
    /// Information about the server.
    let serverInfo: MCPServerInfo?

    enum CodingKeys: String, CodingKey {
        case protocolVersion, capabilities, serverInfo
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try container.decodeIfPresent(String.self, forKey: .protocolVersion)
        capabilities = try container.decodeIfPresent(
            MCPServerCapabilities.self, forKey: .capabilities)
        serverInfo = try container.decodeIfPresent(MCPServerInfo.self, forKey: .serverInfo)
    }
}

/// Capabilities of the MCP server.
struct MCPServerCapabilities: Decodable, Sendable {
    /// Supported tool features.
    let tools: [String: Bool]?
    /// Supported resource features.
    let resources: [String: Bool]?
    /// Supported prompt features.
    let prompts: [String: Bool]?
}

/// Information about the MCP server.
struct MCPServerInfo: Decodable, Sendable {
    /// The server name.
    let name: String
    /// The server version.
    let version: String?
}

/// Information about an available tool.
struct MCPToolInfo: Decodable, Sendable {
    /// The name of the tool.
    let name: String
    /// The description of the tool.
    let description: String?
    /// The input schema for the tool.
    let inputSchema: MCPInputSchema?
}

/// Schema defining the structure of tool inputs.
struct MCPInputSchema: Decodable, Sendable {
    /// The type of the input (usually "object").
    let type: String
    /// The properties allowed in the input.
    let properties: [String: MCPPropertySchema]?
    /// The required properties.
    let required: [String]?
}

/// Schema for a single property in an input schema.
struct MCPPropertySchema: Decodable, Sendable {
    /// The data type of the property.
    let type: String
    /// The description of the property.
    let description: String?
}

/// Result of a tool execution.
struct MCPToolResult: Decodable, Sendable {
    /// The content returned by the tool.
    let content: [MCPContent]
    /// Whether the tool execution resulted in an error.
    let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case content, isError
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decode([MCPContent].self, forKey: .content)
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError)
    }
}

/// Content returned by an MCP tool or resource.
struct MCPContent: Decodable, Sendable {
    /// The type of content (e.g., "text", "image").
    let type: String
    /// Text content.
    let text: String?
    /// Base64 encoded data.
    let data: String?
    /// MIME type of the data.
    let mimeType: String?
}

/// Information about an available resource.
struct MCPResource: Decodable, Sendable {
    /// The URI of the resource.
    let uri: String
    /// The name of the resource.
    let name: String
    /// The description of the resource.
    let description: String?
    /// The MIME type of the resource.
    let mimeType: String?
}

/// Content of a read resource.
struct MCPResourceContent: Decodable, Sendable {
    /// The list of items in the resource content.
    let contents: [MCPResourceItem]

    enum CodingKeys: String, CodingKey {
        case contents
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contents = try container.decode([MCPResourceItem].self, forKey: .contents)
    }
}

/// A single item in a resource content.
struct MCPResourceItem: Decodable, Sendable {
    /// The URI of the item.
    let uri: String
    /// The MIME type of the item.
    let mimeType: String?
    /// The text content of the item.
    let text: String?
    /// The binary content of the item (base64).
    let blob: String?
}

// MARK: - Errors

/// Errors specific to MCP operations.
enum MCPError: LocalizedError {
    /// The client is not connected to the server.
    case notConnected
    /// The connection attempt failed.
    case connectionFailed(String)
    /// The connection was closed unexpectedly.
    case connectionClosed
    /// The server returned an invalid response.
    case invalidResponse(String)
    /// The tool execution failed.
    case toolCallFailed(String)
    /// The request timed out.
    case timeout

    /// A localized description of the error.
    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to MCP server"
        case .connectionFailed(let reason): return "Connection failed: \(reason)"
        case .connectionClosed: return "Connection closed"
        case .invalidResponse(let reason): return "Invalid response: \(reason)"
        case .toolCallFailed(let reason): return "Tool call failed: \(reason)"
        case .timeout: return "Request timed out"
        }
    }
}

// MARK: - AnyCodable Helper

/// A type-erased Codable wrapper for handling arbitrary JSON data.
struct AnyCodable: Codable, @unchecked Sendable {
    /// The wrapped value.
    nonisolated(unsafe) let value: Any

    /// Initializes a new `AnyCodable` with a value.
    init(_ value: Any) {
        self.value = value
    }

    /// Initializes a new `AnyCodable` by decoding.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Cannot decode value")
        }
    }

    /// Encodes the wrapped value.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: encoder.codingPath, debugDescription: "Cannot encode value"))
        }
    }
}
