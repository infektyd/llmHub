//
//  SharedTypes.swift
//  llmHub
//
//  Created by Assistant on 12/10/25.
//

import Foundation
import SwiftUI

#if os(iOS)
    import UIKit
#endif

// MARK: - Shared Types

/// Represents the platform the app is currently running on.
enum CurrentPlatform: String, Sendable {
    case macOS
    case iOS
    case iPadOS
    case unknown

    static var current: CurrentPlatform {
        #if os(macOS)
            return .macOS
        #elseif os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                return .iPadOS
            }
            return .iOS
        #else
            return .unknown
        #endif
    }
}

// MARK: - LLM Request Options

/// User preference for whether the app should request model "thinking"/reasoning output.
enum ThinkingPreference: String, Codable, CaseIterable, Sendable {
    /// Enable thinking only when the selected model/provider supports it.
    case auto
    /// Force-enable thinking when supported; otherwise ignore.
    case on
    /// Never request thinking; still parse/emit if returned anyway.
    case off

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .on: "On"
        case .off: "Off"
        }
    }

    var iconSystemName: String {
        switch self {
        case .auto: "brain"
        case .on: "brain.head.profile"
        case .off: "bolt.slash"
        }
    }
}

/// Cross-provider request options that are not part of message history.
struct LLMRequestOptions: Sendable {
    var thinkingPreference: ThinkingPreference = .auto
    /// Optional provider-specific thinking budget hint.
    var thinkingBudgetTokens: Int? = nil
    /// Optional provider-specific temperature override.
    ///
    /// When set, providers that support sampling temperature should pass this through
    /// to their request payloads.
    var temperatureOverride: Double? = nil
    /// Optional provider-specific thinking level hint (for Gemini 3 models).
    ///
    /// Expected values are model-dependent; see Gemini "Thinking levels" docs.
    /// This is intentionally a free-form string to avoid over-restricting evolving model capabilities.
    var thinkingLevelHint: String? = nil

    static let `default` = LLMRequestOptions()
}

// MARK: - Tool Authorization

/// Status of a permission request for a specific tool.
public enum PermissionStatus: String, Codable, Sendable {
    case notDetermined
    case authorized
    case denied
}

// MARK: - Tool Execution (UI)

/// Represents a running or completed tool execution for the UI.
public struct ToolExecution: Identifiable, Sendable {
    public let id: String
    public let toolID: String
    public let name: String
    public let icon: String
    public var status: ExecutionStatus
    public var output: String
    public let timestamp: Date

    public enum ExecutionStatus: String, Sendable {
        case running
        case completed
        case failed

        var color: Color {
            switch self {
            case .running: return .blue
            case .completed: return .green
            case .failed: return .red
            }
        }
    }

    public init(
        id: String = UUID().uuidString, toolID: String, name: String, icon: String,
        status: ExecutionStatus = .running, output: String = "", timestamp: Date = Date()
    ) {
        self.id = id
        self.toolID = toolID
        self.name = name
        self.icon = icon
        self.status = status
        self.output = output
        self.timestamp = timestamp
    }
}

// MARK: - Tool Toggle (UI)

/// Represents a tool toggle switch in the chat input panel.
public struct UIToolToggleItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let icon: String
    public let description: String
    public var isEnabled: Bool
    public var isAvailable: Bool
    public var unavailableReason: String?

    public init(
        id: String, name: String, icon: String, description: String, isEnabled: Bool = false,
        isAvailable: Bool = true, unavailableReason: String? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.description = description
        self.isEnabled = isEnabled
        self.isAvailable = isAvailable
        self.unavailableReason = unavailableReason
    }
}

// MARK: - Streaming Accumulator

/// Helper struct to accumulate partial tool calls during streaming.
struct PendingToolCall {
    let index: Int
    var id: String?
    var name: String?
    var arguments: String
}
