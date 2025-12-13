//
//  MCPToolBridge.swift
//  llmHub
//
//  Bridge between MCP servers and the native Tool protocol
//  Discovers and wraps MCP tools for use in the ToolRegistry
//

import Foundation
import OSLog

/// Manages MCP server connections and bridges their tools to the native Tool protocol.
actor MCPToolBridge {
    private let logger = Logger(subsystem: "com.llmhub", category: "MCPToolBridge")

    private var clients: [UUID: MCPClient] = [:]
    private var discoveredTools: [String: MCPBridgedTool] = [:]

    // User Defaults key for storing server configurations
    private let configKey = "mcp.serverConfigs"

    // MARK: - Server Management

    /// Load saved server configurations from UserDefaults.
    /// - Returns: An array of `MCPServerConfig`.
    func loadConfigurations() -> [MCPServerConfig] {
        guard let data = UserDefaults.standard.data(forKey: configKey),
            let configs = try? JSONDecoder().decode([MCPServerConfig].self, from: data)
        else {
            return []
        }
        return configs
    }

    /// Save server configurations to UserDefaults.
    /// - Parameter configs: The configurations to save.
    func saveConfigurations(_ configs: [MCPServerConfig]) {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    /// Add a new MCP server configuration.
    /// - Parameter config: The configuration to add.
    func addServer(_ config: MCPServerConfig) {
        var configs = loadConfigurations()
        configs.append(config)
        saveConfigurations(configs)
    }

    /// Remove an MCP server configuration by ID.
    /// - Parameter id: The ID of the server configuration to remove.
    func removeServer(id: UUID) {
        var configs = loadConfigurations()
        configs.removeAll { $0.id == id }
        saveConfigurations(configs)

        // Disconnect if connected
        if let client = clients.removeValue(forKey: id) {
            Task { await client.disconnect() }
        }
    }

    /// Update an MCP server configuration.
    /// - Parameter config: The updated configuration.
    func updateServer(_ config: MCPServerConfig) {
        var configs = loadConfigurations()
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
            saveConfigurations(configs)
        }
    }

    // MARK: - Connection Management

    /// Connect to all enabled MCP servers.
    func connectAll() async {
        let configs = loadConfigurations().filter { $0.isEnabled }

        for config in configs {
            await connect(to: config)
        }
    }

    /// Connect to a specific MCP server.
    /// - Parameter config: The configuration of the server to connect to.
    func connect(to config: MCPServerConfig) async {
        guard clients[config.id] == nil else {
            logger.debug("Already connected to: \(config.name)")
            return
        }

        let client = MCPClient(config: config)

        do {
            try await client.connect()
            clients[config.id] = client
            logger.info("Connected to MCP server: \(config.name)")

            // Discover tools
            await discoverTools(from: client, serverID: config.id)

        } catch {
            logger.error("Failed to connect to \(config.name): \(error)")
        }
    }

    /// Disconnect from a specific MCP server.
    /// - Parameter serverID: The ID of the server to disconnect from.
    func disconnect(serverID: UUID) async {
        guard let client = clients.removeValue(forKey: serverID) else { return }

        await client.disconnect()

        // Remove tools from this server
        discoveredTools = discoveredTools.filter { $0.value.serverID != serverID }

        logger.info("Disconnected from MCP server: \(serverID)")
    }

    /// Disconnect from all MCP servers.
    func disconnectAll() async {
        for (_, client) in clients {
            await client.disconnect()
        }
        clients.removeAll()
        discoveredTools.removeAll()
    }

    // MARK: - Tool Discovery

    /// Discover tools from a connected MCP server.
    /// - Parameters:
    ///   - client: The MCP client.
    ///   - serverID: The server ID.
    private func discoverTools(from client: MCPClient, serverID: UUID) async {
        do {
            let tools = try await client.listTools()

            for toolInfo in tools {
                let bridgedTool = MCPBridgedTool(
                    serverID: serverID,
                    client: client,
                    toolInfo: toolInfo
                )

                // Use qualified name to avoid conflicts
                let qualifiedName = "mcp_\(serverID.uuidString.prefix(8))_\(toolInfo.name)"
                discoveredTools[qualifiedName] = bridgedTool

                logger.info("Discovered MCP tool: \(toolInfo.name) -> \(qualifiedName)")
            }

        } catch {
            logger.error("Failed to discover tools: \(error)")
        }
    }

    // MARK: - Tool Access

    /// Get all bridged tools as an array.
    /// - Returns: An array of tools.
    var allTools: [any Tool] {
        Array(discoveredTools.values)
    }

    /// Get a specific bridged tool by name.
    /// - Parameter name: The name of the tool.
    /// - Returns: The tool if found.
    func tool(named name: String) -> (any Tool)? {
        discoveredTools[name]
    }

    /// Register all MCP tools into a ToolRegistry.
    /// Returns the tools to be registered externally.
    /// - Returns: An array of tools.
    func getToolsForRegistration() -> [any Tool] {
        Array(discoveredTools.values)
    }

    // MARK: - Status

    /// Check if connected to any MCP servers.
    var isConnected: Bool {
        !clients.isEmpty
    }

    /// Get connection status for all configured servers.
    /// - Returns: An array of tuples containing config and connection status.
    func connectionStatus() -> [(config: MCPServerConfig, isConnected: Bool)] {
        let configs = loadConfigurations()
        return configs.map { config in
            (config, clients[config.id] != nil)
        }
    }
}

// MARK: - MCPBridgedTool

/// A Tool implementation that bridges to an MCP server tool.
/// Uses @unchecked Sendable because it manages its state carefully.
nonisolated final class MCPBridgedTool: Tool, @unchecked Sendable {
    let id: String
    let name: String
    let description: String

    let serverID: UUID
    private let client: MCPClient
    private let logger = Logger(subsystem: "com.llmhub", category: "MCPBridgedTool")

    // Cached schema
    let parameters: ToolParametersSchema

    /// Initializes a new bridged tool.
    /// - Parameters:
    ///   - serverID: The ID of the MCP server.
    ///   - client: The MCP client.
    ///   - toolInfo: Information about the tool from the server.
    nonisolated init(serverID: UUID, client: MCPClient, toolInfo: MCPToolInfo) {
        self.serverID = serverID
        self.client = client
        self.id = "mcp_\(serverID.uuidString.prefix(8))_\(toolInfo.name)"
        self.name = toolInfo.name
        self.description = toolInfo.description ?? "MCP tool: \(toolInfo.name)"

        // Convert MCP input schema to key-value properties
        if let schema = toolInfo.inputSchema, let props = schema.properties {
            var properties: [String: ToolProperty] = [:]
            for (key, prop) in props {
                // Map type string to JSONSchemaType
                let schemaType = JSONSchemaType(rawValue: prop.type) ?? .string
                properties[key] = ToolProperty(
                    type: schemaType,
                    description: prop.description ?? ""
                )
            }

            self.parameters = ToolParametersSchema(
                properties: properties,
                required: schema.required ?? []
            )
        } else {
            self.parameters = ToolParametersSchema(properties: [:], required: [])
        }
    }

    // Tool Protocol Default Properties
    var permissionLevel: ToolPermissionLevel { .dangerous }  // Treat external tools as dangerous by default
    var requiredCapabilities: [ToolCapability] { [.networkIO] }  // Needs network to talk to MCP server
    var weight: ToolWeight { .heavy }
    var isCacheable: Bool { false }

    /// Executes the tool via the MCP client.
    /// - Parameter arguments: The input arguments.
    /// - Returns: The tool output as a structured result.
    func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        logger.info("Calling MCP tool: \(self.name)")

        do {
            // Convert ToolArguments back to MCPJSONValue for the client
            // This is a simplified conversion, might need robust serialization
            let argsDict = arguments.dictionary
            let mcpArgs = MCPJSONValue.object(argsDict.mapValues { MCPJSONValue.from($0) })

            let result = try await client.callTool(name: name, arguments: mcpArgs)

            // Format the result
            var output = ""
            for content in result.content {
                switch content.type {
                case "text":
                    output += content.text ?? ""
                case "image":
                    if let mimeType = content.mimeType, let data = content.data {
                        output += "[Image: \(mimeType), \(data.count) bytes]\n"
                    }
                case "resource":
                    output += "[Resource]\n"
                default:
                    output += "[Unknown content type: \(content.type)]\n"
                }
            }

            if result.isError == true {
                throw ToolError.executionFailed(output, retryable: false)
            }

            let finalOutput = output.isEmpty ? "(No output)" : output
            return await MainActor.run {
                ToolResult.success(finalOutput)
            }

        } catch let error as MCPError {
            logger.error("MCP tool call failed: \(error)")
            throw ToolError.executionFailed(error.localizedDescription, retryable: false)
        }
    }
}

// MARK: - Default Server Configurations

extension MCPToolBridge {
    /// Get some example MCP server configurations.
    static var exampleConfigurations: [MCPServerConfig] {
        [
            // Filesystem MCP server (Node.js)
            MCPServerConfig(
                name: "Filesystem",
                command: "/usr/local/bin/npx",
                args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
                env: nil,
                isEnabled: false
            ),
            // Git MCP server
            MCPServerConfig(
                name: "Git",
                command: "/usr/local/bin/npx",
                args: ["-y", "@modelcontextprotocol/server-git"],
                env: nil,
                isEnabled: false
            ),
            // Memory MCP server
            MCPServerConfig(
                name: "Memory",
                command: "/usr/local/bin/npx",
                args: ["-y", "@modelcontextprotocol/server-memory"],
                env: nil,
                isEnabled: false
            ),
        ]
    }
}

// MARK: - MCPToolManager (Singleton)

/// Global manager for MCP tool bridge.
/// Use this to access MCP tools throughout the app.
final class MCPToolManager: @unchecked Sendable {
    /// Shared singleton instance.
    static let shared = MCPToolManager()

    private let bridge = MCPToolBridge()
    private let logger = Logger(subsystem: "com.llmhub", category: "MCPToolManager")

    private init() {}

    /// Initialize and connect to all enabled MCP servers.
    func initialize() async {
        await bridge.connectAll()
        logger.info("MCP Tool Manager initialized")
    }

    /// Get all available MCP tools.
    var tools: [any Tool] {
        get async {
            await bridge.allTools
        }
    }

    /// Register all MCP tools into a registry.
    /// - Parameter registry: The registry to register tools into.
    func registerTools(into registry: ToolRegistry) async {
        let tools = await bridge.getToolsForRegistration()
        await registry.register(tools)
    }

    /// Add a new MCP server.
    /// - Parameter config: The server configuration.
    func addServer(_ config: MCPServerConfig) async {
        await bridge.addServer(config)
        if config.isEnabled {
            await bridge.connect(to: config)
        }
    }

    /// Remove an MCP server.
    /// - Parameter id: The server ID.
    func removeServer(id: UUID) async {
        await bridge.removeServer(id: id)
    }

    /// Get connection status.
    /// - Returns: Array of configuration and connection status.
    func connectionStatus() async -> [(config: MCPServerConfig, isConnected: Bool)] {
        await bridge.connectionStatus()
    }

    /// Disconnect from all servers.
    func shutdown() async {
        await bridge.disconnectAll()
    }
}
