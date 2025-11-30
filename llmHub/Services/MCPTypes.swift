//
//  MCPTypes.swift
//  llmHub
//
//  Data types for Model Context Protocol (MCP)
//

import Foundation

// MARK: - MCP Data Types

struct MCPServerConfig: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    let name: String
    let command: String
    let args: [String]
    let env: [String: String]?
    var isEnabled: Bool = true
}

// Empty params struct for requests that don't need params
struct EmptyParams: Encodable, Sendable {
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

struct MCPToolCallParams: Encodable, Sendable {
    let name: String
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

struct MCPResourceReadParams: Encodable, Sendable {
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
enum MCPJSONValue: Encodable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([MCPJSONValue])
    case object([String: MCPJSONValue])

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
            try container.encode(d)
        case .string(let s):
            try container.encode(s)
        case .array(let arr):
            try container.encode(arr)
        case .object(let dict):
            try container.encode(dict)
        }
    }
}

struct MCPRequest<T: Encodable & Sendable>: Encodable, Sendable {
    let jsonrpc: String
    let id: Int
    let method: String
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

struct MCPNotification<T: Encodable & Sendable>: Encodable, Sendable {
    let jsonrpc: String
    let method: String
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

struct MCPResponse: Decodable, Sendable {
    let jsonrpc: String
    let id: Int?
    let result: AnySendable?
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

/// Thread-safe wrapper for Any values
struct AnySendable: @unchecked Sendable {
    nonisolated let value: Any

    nonisolated init(_ value: Any) {
        self.value = value
    }
}

struct MCPErrorInfo: Decodable, Sendable {
    let code: Int
    let message: String
    let data: String?
}

struct MCPInitializeParams: Encodable, Sendable {
    let protocolVersion: String
    let capabilities: MCPClientCapabilities
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

struct MCPClientCapabilities: Encodable, Sendable {
    // Empty for now - add capabilities as needed
    nonisolated init() {}

    nonisolated func encode(to encoder: Encoder) throws {
        var _ = encoder.container(keyedBy: CodingKeys.self)
    }
    enum CodingKeys: String, CodingKey {
        case none  // Dummy case to satisfy CodingKey requirement if needed, or just use empty container
    }
}

struct MCPClientInfo: Encodable, Sendable {
    let name: String
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

struct MCPInitializeResult: Decodable, Sendable {
    let protocolVersion: String?
    let capabilities: MCPServerCapabilities?
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

struct MCPServerCapabilities: Decodable, Sendable {
    let tools: [String: Bool]?
    let resources: [String: Bool]?
    let prompts: [String: Bool]?
}

struct MCPServerInfo: Decodable, Sendable {
    let name: String
    let version: String?
}

struct MCPToolInfo: Decodable, Sendable {
    let name: String
    let description: String?
    let inputSchema: MCPInputSchema?
}

struct MCPInputSchema: Decodable, Sendable {
    let type: String
    let properties: [String: MCPPropertySchema]?
    let required: [String]?
}

struct MCPPropertySchema: Decodable, Sendable {
    let type: String
    let description: String?
}

struct MCPToolResult: Decodable, Sendable {
    let content: [MCPContent]
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

struct MCPContent: Decodable, Sendable {
    let type: String
    let text: String?
    let data: String?
    let mimeType: String?
}

struct MCPResource: Decodable, Sendable {
    let uri: String
    let name: String
    let description: String?
    let mimeType: String?
}

struct MCPResourceContent: Decodable, Sendable {
    let contents: [MCPResourceItem]

    enum CodingKeys: String, CodingKey {
        case contents
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contents = try container.decode([MCPResourceItem].self, forKey: .contents)
    }
}

struct MCPResourceItem: Decodable, Sendable {
    let uri: String
    let mimeType: String?
    let text: String?
    let blob: String?
}

// MARK: - Errors

enum MCPError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case connectionClosed
    case invalidResponse(String)
    case toolCallFailed(String)
    case timeout

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

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

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
