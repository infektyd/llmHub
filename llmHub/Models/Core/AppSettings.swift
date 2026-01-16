//
//  AppSettings.swift
//  llmHub
//
//  Complete application settings data model with UserDefaults persistence.
//  No glass effects, flat matte design with AppColors system.
//

import Foundation
import SwiftUI

// MARK: - Color Scheme Choice

/// User's preferred color scheme override.
public enum ColorSchemeChoice: String, Codable, CaseIterable, Sendable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var iconSystemName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// Convert to SwiftUI ColorScheme for `.preferredColorScheme()` modifier
    var toColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - App Settings

/// Complete application settings model.
/// Persisted to UserDefaults with automatic encoding/decoding.
public struct AppSettings: Codable, Sendable {

    /// UserDefaults key for persisted settings data.
    public static let storageKey = "llmHub.appSettings.v1"

    // MARK: - Appearance

    /// User's preferred color scheme (.system, .light, .dark)
    public var colorScheme: ColorSchemeChoice = .system

    /// Reduces vertical spacing throughout the UI (12pt → 8pt)
    public var compactMode: Bool = false

    /// Display token usage and cost in message headers
    public var showTokenCounts: Bool = true

    /// Font size scale factor (0.8 - 1.5, default 1.0)
    public var fontSize: CGFloat = 1.0

    /// Emoji/avatar shown next to the user's messages in the transcript.
    public var userEmote: String = "🧑‍💻"

    // MARK: - Tools & Behavior

    /// Per-tool permissions (tool ID → enabled state)
    public var defaultToolPermissions: [String: Bool] = [:]

    /// Auto-scroll to newest messages
    public var autoScroll: Bool = true

    /// Max streaming updates per second (5-20, default 10)
    public var streamingThrottle: Int = 10

    /// Enable context compaction to stay within token limits
    public var contextCompactionEnabled: Bool = true

    /// Enables developer-only UI features (manual tool triggering)
    public var developerModeManualToolTriggering: Bool = false

    // MARK: - Provider Defaults

    /// Default provider ID to select on launch
    public var defaultProviderID: String = "openai"

    /// Default model name to select on launch
    public var defaultModel: String = "gpt-4o"

    // MARK: - Workspace

    /// Maximum number of recent sessions to keep in sidebar (10-50, default 20)
    public var recentSessionLimit: Int = 20

    /// Auto-save interval in seconds (10-300, default 30)
    public var autoSaveInterval: Double = 30.0

    // MARK: - Advanced

    /// Network timeout for API requests in seconds (10-120, default 60)
    public var networkTimeout: TimeInterval = 60.0

    /// Maximum context window tokens (1000-200000, default 128000)
    public var maxContextTokens: Int = 128000

    /// Enable automatic conversation summary generation
    public var summaryGenerationEnabled: Bool = true

    /// Enable smart tool run labels for run bundles
    public var smartRunLabelsEnabled: Bool = false

    // MARK: - Initialization

    public init() {
        // Use default values defined above
    }

    private enum CodingKeys: String, CodingKey {
        case colorScheme
        case compactMode
        case showTokenCounts
        case fontSize
        case userEmote
        case defaultToolPermissions
        case autoScroll
        case streamingThrottle
        case contextCompactionEnabled
        case developerModeManualToolTriggering
        case defaultProviderID
        case defaultModel
        case recentSessionLimit
        case autoSaveInterval
        case networkTimeout
        case maxContextTokens
        case summaryGenerationEnabled
        case smartRunLabelsEnabled
    }

    public init(from decoder: Decoder) throws {
        let defaults = AppSettings.defaultSettings
        let container = try decoder.container(keyedBy: CodingKeys.self)

        colorScheme = try container.decodeIfPresent(ColorSchemeChoice.self, forKey: .colorScheme)
            ?? defaults.colorScheme
        compactMode = try container.decodeIfPresent(Bool.self, forKey: .compactMode)
            ?? defaults.compactMode
        showTokenCounts = try container.decodeIfPresent(Bool.self, forKey: .showTokenCounts)
            ?? defaults.showTokenCounts
        fontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize)
            ?? defaults.fontSize
        userEmote = try container.decodeIfPresent(String.self, forKey: .userEmote)
            ?? defaults.userEmote

        defaultToolPermissions =
            try container.decodeIfPresent([String: Bool].self, forKey: .defaultToolPermissions)
            ?? defaults.defaultToolPermissions
        autoScroll = try container.decodeIfPresent(Bool.self, forKey: .autoScroll)
            ?? defaults.autoScroll
        streamingThrottle = try container.decodeIfPresent(Int.self, forKey: .streamingThrottle)
            ?? defaults.streamingThrottle
        contextCompactionEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .contextCompactionEnabled)
            ?? defaults.contextCompactionEnabled
        developerModeManualToolTriggering =
            try container.decodeIfPresent(Bool.self, forKey: .developerModeManualToolTriggering)
            ?? defaults.developerModeManualToolTriggering

        defaultProviderID = try container.decodeIfPresent(String.self, forKey: .defaultProviderID)
            ?? defaults.defaultProviderID
        defaultModel = try container.decodeIfPresent(String.self, forKey: .defaultModel)
            ?? defaults.defaultModel
        recentSessionLimit = try container.decodeIfPresent(Int.self, forKey: .recentSessionLimit)
            ?? defaults.recentSessionLimit
        autoSaveInterval = try container.decodeIfPresent(Double.self, forKey: .autoSaveInterval)
            ?? defaults.autoSaveInterval
        networkTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .networkTimeout)
            ?? defaults.networkTimeout
        maxContextTokens = try container.decodeIfPresent(Int.self, forKey: .maxContextTokens)
            ?? defaults.maxContextTokens
        summaryGenerationEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .summaryGenerationEnabled)
            ?? defaults.summaryGenerationEnabled
        smartRunLabelsEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .smartRunLabelsEnabled)
            ?? defaults.smartRunLabelsEnabled
    }

    // MARK: - Validation

    /// Validates and clamps all settings to their acceptable ranges.
    /// Called automatically when loading from UserDefaults.
    public mutating func validate() {
        // Clamp font size
        fontSize = max(0.8, min(1.5, fontSize))

        // Ensure user emote is never empty
        if userEmote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userEmote = "🧑‍💻"
        }

        // Clamp streaming throttle
        streamingThrottle = max(5, min(20, streamingThrottle))

        // Clamp recent session limit
        recentSessionLimit = max(10, min(50, recentSessionLimit))

        // Clamp auto-save interval
        autoSaveInterval = max(10, min(300, autoSaveInterval))

        // Clamp network timeout
        networkTimeout = max(10, min(120, networkTimeout))

        // Clamp max context tokens
        maxContextTokens = max(1000, min(200000, maxContextTokens))
    }

    // MARK: - Default Values

    /// Returns a fresh instance with all default values.
    public static let defaultSettings = AppSettings()

    /// Loads settings from UserDefaults, falling back to defaults if missing or invalid.
    public static func load(from userDefaults: UserDefaults = .standard) -> AppSettings {
        guard let data = userDefaults.data(forKey: storageKey),
            var loaded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return .defaultSettings
        }
        loaded.validate()
        return loaded
    }
}

// MARK: - Bundle Extension

extension Bundle {
    var buildNumber: String? {
        infoDictionary?["CFBundleVersion"] as? String
    }

    var versionNumber: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
