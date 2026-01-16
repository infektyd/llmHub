//
//  ToolEnvironment.swift
//  llmHub
//
//  Defines platform-aware capabilities and availability for tools.
//
//

import Foundation
import os

/// Structured reasons why a tool may be unavailable.
enum ToolUnavailableReason: Sendable, Equatable {
    /// The tool is not supported on this platform (e.g., iOS vs macOS).
    case unsupportedOnPlatform
    /// Required backend service is not running or available.
    case missingBackend
    /// User or system has denied permission.
    case permissionDenied
    /// User has explicitly disabled this tool.
    case disabledByUser
    /// The current model doesn't support this tool.
    case modelIncompatible
    /// Tool requires configuration (API keys, database connection, etc.).
    case notConfigured
    /// Path or operation is outside allowed sandbox.
    case sandboxRestriction

    /// Human-readable description for this reason.
    nonisolated var description: String {
        switch self {
        case .unsupportedOnPlatform:
            return "unsupportedOnPlatform"
        case .missingBackend:
            return "missingBackend"
        case .permissionDenied:
            return "permissionDenied"
        case .disabledByUser:
            return "disabledByUser"
        case .modelIncompatible:
            return "modelIncompatible"
        case .notConfigured:
            return "notConfigured"
        case .sandboxRestriction:
            return "sandboxRestriction"
        }
    }
}

/// Descriptor for a tool parameter in the input schema.
struct ToolParameter: Sendable, Equatable {
    let name: String
    let type: String
    let description: String
    let required: Bool
    let enumValues: [String]?

    nonisolated init(
        name: String, type: String, description: String, required: Bool = false,
        enumValues: [String]? = nil
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
        self.enumValues = enumValues
    }
}

/// Descriptor for a tool that can be serialized for LLM consumption.
struct ToolDescriptor: Sendable, Equatable {
    let name: String
    let description: String
    let parameters: [ToolParameter]
    let availability: ToolAvailability
}

/// Describes the current execution environment for tools.
struct ToolEnvironment: Sendable {
    /// Supported platforms.
    enum Platform: String, Sendable {
        case iOS
        case macOS
    }

    /// The current platform.
    let platform: Platform
    /// Indicates if running in a simulator.
    let isSimulator: Bool
    /// Indicates if a code execution backend is reachable.
    let hasCodeExecutionBackend: Bool
    /// Optional sandbox root directory.
    let sandboxRoot: URL?

    /// Convenience for building the current environment snapshot.
    nonisolated(unsafe) static var current: ToolEnvironment {
        #if os(iOS)
            let platform: Platform = .iOS
            let isSimulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                .first

            let hasCodeExecutionBackend = true

            return ToolEnvironment(
                platform: platform,
                isSimulator: isSimulator,
                hasCodeExecutionBackend: hasCodeExecutionBackend,
                sandboxRoot: documents
            )
        #else
            let platform: Platform = .macOS
            let hasBackend = detectCodeExecutionBackend()
            return ToolEnvironment(
                platform: platform,
                isSimulator: false,
                hasCodeExecutionBackend: hasBackend,
                sandboxRoot: WorkspaceResolver.resolve(platform: platform)
            )
        #endif
    }

    /// Whether the environment supports the requested capability.
    /// - Parameter capability: The capability to check.
    nonisolated func supports(_ capability: ToolCapability) -> Bool {
        switch capability {
        case .fileSystem, .fileRead, .fileWrite, .workspace:
            // Read is mostly supported, Write limited on iOS
            return true
        case .networkIO, .webAccess, .imageGeneration:
            return true
        case .shellExecution:
            return platform == .macOS
        case .codeExecution:
            #if os(iOS)
                return hasCodeExecutionBackend
            #else
                return platform == .macOS && hasCodeExecutionBackend
            #endif
        case .browserControl:
            return platform == .macOS
        case .systemEvents:
            return platform == .macOS
        case .dbAccess, .notifications, .scheduleTasks:
            return true
        }
    }

    /// Returns structured availability information when a capability is unavailable.
    /// - Parameter capability: The capability being checked.
    nonisolated func unavailabilityInfo(for capability: ToolCapability) -> (
        reason: ToolUnavailableReason, details: String
    ) {
        switch capability {
        case .fileSystem, .fileRead, .fileWrite, .workspace:
            return (.permissionDenied, "File system access is restricted.")
        case .networkIO, .webAccess, .imageGeneration:
            return (.missingBackend, "Network access is unavailable.")
        case .shellExecution:
            if platform == .iOS {
                return (.unsupportedOnPlatform, "Shell access is not permitted on iOS.")
            }
            return (.permissionDenied, "Shell access is disabled.")
        case .codeExecution:
            if platform == .iOS {
                return (.missingBackend, "Code execution backend is not available on this device.")
            }
            return (.missingBackend, "Code execution backend is not running.")
        case .browserControl:
            if platform == .iOS {
                return (.unsupportedOnPlatform, "Browser control is not supported on iOS.")
            }
            return (.permissionDenied, "Browser control restricted.")
        case .systemEvents:
            if platform == .iOS {
                return (.unsupportedOnPlatform, "System events not supported on iOS.")
            }
            return (.permissionDenied, "System events restricted.")
        case .dbAccess:
            return (.notConfigured, "Database access is not configured.")
        case .notifications:
            return (.permissionDenied, "Notifications access is restricted.")
        case .scheduleTasks:
            return (.permissionDenied, "Task scheduling is restricted.")
        }
    }

    /// Returns a human-readable reason when a capability is unavailable (legacy method).
    /// - Parameter capability: The capability being checked.
    nonisolated func unsupportedReason(for capability: ToolCapability) -> String {
        return unavailabilityInfo(for: capability).details
    }

    /// Checks whether a URL is inside the app sandbox (iOS) or allowed paths (macOS).
    /// - Parameter url: The URL to evaluate.
    nonisolated func isURLInsideSandbox(_ url: URL) -> Bool {
        guard let sandboxRoot else { return true }
        let standardizedRoot = sandboxRoot.standardizedFileURL
        let standardizedURL = url.standardizedFileURL
        return standardizedURL.path.hasPrefix(standardizedRoot.path)
    }

    /// Evaluates a list of capabilities and returns an availability result.
    /// - Parameter capabilities: The capabilities required by a tool.
    nonisolated func availability(for capabilities: [ToolCapability]) -> ToolAvailability {
        for capability in capabilities {
            if !supports(capability) {
                let info = unavailabilityInfo(for: capability)
                return .unavailable(reason: info.details)
            }
        }
        return .available
    }
}

#if os(macOS)
    extension ToolEnvironment {
        fileprivate nonisolated static func detectCodeExecutionBackend(timeout: TimeInterval = 1.0)
            -> Bool {
            let availabilityState = OSAllocatedUnfairLock(initialState: false)
            let semaphore = DispatchSemaphore(value: 0)

            Task.detached {
                let backend = XPCExecutionBackend.shared
                let availability = await backend.isAvailable
                availabilityState.withLock { $0 = availability }
                semaphore.signal()
            }

            let waitResult = semaphore.wait(timeout: .now() + timeout)
            guard waitResult == .success else {
                return false
            }

            return availabilityState.withLock { $0 }
        }
    }
#else
    extension ToolEnvironment {
        fileprivate nonisolated static func detectCodeExecutionBackend(timeout: TimeInterval = 1.0)
            -> Bool {
            #if os(iOS)
            return true
            #else
            return frameworkLinked("Python")
            #endif
        }
    }
#endif

#if !os(macOS)
    extension ToolEnvironment {
        fileprivate nonisolated static func frameworkLinked(_ name: String) -> Bool {
            let fileManager = FileManager.default
            let candidates: [URL] = [
                Bundle.main.privateFrameworksURL?.appendingPathComponent("\(name).framework"),
                Bundle.main.bundleURL.appendingPathComponent("Frameworks/\(name).framework")
            ].compactMap { $0 }

            return candidates.contains { fileManager.fileExists(atPath: $0.path) }
        }
    }
#endif

