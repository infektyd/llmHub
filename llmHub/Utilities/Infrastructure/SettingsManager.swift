//
//  SettingsManager.swift
//  llmHub
//
//  Manages AppSettings persistence to UserDefaults with validation and automatic saving.
//  Observable wrapper for SwiftUI integration.
//

import Combine
import Foundation
import SwiftUI

/// Manages application settings persistence and provides observable access for SwiftUI.
@MainActor
@Observable
public final class SettingsManager {

    // MARK: - Published Settings

    /// Current app settings (automatically persisted on change)
    public var settings: AppSettings {
        didSet {
            saveSettings()
        }
    }

    // MARK: - Constants

    private static let settingsKey = "llmHub.appSettings.v1"

    // MARK: - Private Properties

    private let userDefaults: UserDefaults
    private var saveDebounceTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // Load settings from UserDefaults or use defaults
        if let data = userDefaults.data(forKey: Self.settingsKey),
            var loadedSettings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            // Validate loaded settings
            loadedSettings.validate()
            self.settings = loadedSettings
        } else {
            // Use default settings
            self.settings = .defaultSettings
            // Save defaults immediately
            saveSettingsImmediately()
        }
    }

    // MARK: - Public Methods

    /// Saves settings immediately (synchronous).
    public func saveSettingsImmediately() {
        var validatedSettings = settings
        validatedSettings.validate()

        guard let data = try? JSONEncoder().encode(validatedSettings) else {
            print("⚠️ Failed to encode AppSettings")
            return
        }

        userDefaults.set(data, forKey: Self.settingsKey)
        userDefaults.synchronize()
    }

    /// Resets all settings to defaults.
    public func resetToDefaults() {
        settings = .defaultSettings
        saveSettingsImmediately()
    }

    /// Exports settings as JSON string (for debugging/backup).
    public func exportSettingsJSON() -> String? {
        guard let data = try? JSONEncoder().encode(settings),
            let jsonString = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return jsonString
    }

    /// Imports settings from JSON string.
    public func importSettingsJSON(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8),
            var importedSettings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return false
        }
        importedSettings.validate()
        settings = importedSettings
        return true
    }

    // MARK: - Convenience Accessors

    /// Get/set color scheme choice
    public var colorScheme: ColorSchemeChoice {
        get { settings.colorScheme }
        set { settings.colorScheme = newValue }
    }

    /// Get/set compact mode
    public var compactMode: Bool {
        get { settings.compactMode }
        set { settings.compactMode = newValue }
    }

    /// Get/set show token counts
    public var showTokenCounts: Bool {
        get { settings.showTokenCounts }
        set { settings.showTokenCounts = newValue }
    }

    /// Get/set font size
    public var fontSize: CGFloat {
        get { settings.fontSize }
        set {
            settings.fontSize = max(0.8, min(1.5, newValue))
        }
    }

    /// Get/set auto scroll
    public var autoScroll: Bool {
        get { settings.autoScroll }
        set { settings.autoScroll = newValue }
    }

    /// Get/set streaming throttle
    public var streamingThrottle: Int {
        get { settings.streamingThrottle }
        set {
            settings.streamingThrottle = max(5, min(20, newValue))
        }
    }

    /// Check if a tool is enabled
    public func isToolEnabled(_ toolID: String) -> Bool {
        return settings.defaultToolPermissions[toolID] ?? true
    }

    /// Set tool enabled state
    public func setToolEnabled(_ toolID: String, enabled: Bool) {
        settings.defaultToolPermissions[toolID] = enabled
    }

    // MARK: - Private Methods

    /// Debounced save (prevents excessive UserDefaults writes)
    private func saveSettings() {
        // Cancel previous save task
        saveDebounceTask?.cancel()

        // Schedule new save after 500ms
        saveDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms

            guard !Task.isCancelled else { return }
            self?.saveSettingsImmediately()
        }
    }
}

// MARK: - SwiftUI Environment

private struct SettingsManagerKey: EnvironmentKey {
    static let defaultValue = SettingsManager()
}

extension EnvironmentValues {
    /// Access the global SettingsManager from the environment.
    public var settingsManager: SettingsManager {
        get { self[SettingsManagerKey.self] }
        set { self[SettingsManagerKey.self] = newValue }
    }
}

extension View {
    /// Inject a SettingsManager into the environment.
    public func settingsManager(_ manager: SettingsManager) -> some View {
        environment(\.settingsManager, manager)
    }
}
