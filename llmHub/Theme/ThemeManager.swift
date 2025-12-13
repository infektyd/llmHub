//
//  ThemeManager.swift
//  llmHub
//
//  Manages theme selection and persistence across app launches.
//

import Observation
import SwiftUI

/// Manages the current theme and persists user selection
@Observable
@MainActor
final class ThemeManager {

    // MARK: - Singleton

    static let shared = ThemeManager()

    // MARK: - Properties

    // MARK: - Properties

    /// Currently selected theme
    var current: AppTheme {
        didSet {
            saveSelection()
        }
    }

    /// All available themes
    static let available: [AppTheme] = [
        LiquidGlassTheme(),
        LiquidGlassLightTheme(),  // New Light Theme
        NeonGlassTheme(),
        WarmPaperTheme(),
    ]

    /// Convenience computed property for binding to theme name
    var currentThemeName: String {
        get { current.name }
        set {
            if let theme = Self.available.first(where: { $0.name == newValue }) {
                current = theme
            }
        }
    }

    /// Transcript visualization style
    enum TranscriptStyle: String, CaseIterable, Identifiable {
        case liquidGlassLight = "Liquid Glass Light"  // Existing bubbles
        case neonDark = "Neon Dark"  // New row-based continuous glass

        var id: String { rawValue }
    }

    /// Current transcript style
    var transcriptStyle: TranscriptStyle {
        didSet {
            UserDefaults.standard.set(transcriptStyle.rawValue, forKey: transcriptStyleKey)
        }
    }

    private let userDefaultsKey = "selectedThemeName"
    private let transcriptStyleKey = "transcriptStyle"

    // MARK: - Initialization

    private init() {
        // Load saved theme or default to Liquid Glass
        if let savedName = UserDefaults.standard.string(forKey: userDefaultsKey),
            let savedTheme = Self.available.first(where: { $0.name == savedName })
        {
            self.current = savedTheme
        } else {
            self.current = LiquidGlassTheme()
        }

        // Load saved transcript style or default to neonDark for modern feel
        if let savedStyleRaw = UserDefaults.standard.string(forKey: transcriptStyleKey),
            let style = TranscriptStyle(rawValue: savedStyleRaw)
        {
            self.transcriptStyle = style
        } else {
            self.transcriptStyle = .neonDark
        }
    }

    // MARK: - Public Methods

    /// Sets the current theme
    /// - Parameter theme: The theme to activate
    func setTheme(_ theme: AppTheme) {
        current = theme
    }

    /// Sets the current theme by name
    /// - Parameter themeName: The name of the theme to activate
    func setTheme(named themeName: String) {
        guard let theme = Self.available.first(where: { $0.name == themeName }) else {
            return
        }
        current = theme
    }

    /// Sets the transcript style
    func setTranscriptStyle(_ style: TranscriptStyle) {
        transcriptStyle = style
    }

    /// Cycles to the next available theme
    func cycleTheme() {
        guard let currentIndex = Self.available.firstIndex(where: { $0.name == current.name })
        else {
            return
        }
        let nextIndex = (currentIndex + 1) % Self.available.count
        current = Self.available[nextIndex]
    }

    // MARK: - Private Methods

    /// Persists the current theme selection
    private func saveSelection() {
        UserDefaults.standard.set(current.name, forKey: userDefaultsKey)
    }
}

// MARK: - Environment Integration

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = LiquidGlassTheme()
}

extension EnvironmentValues {
    /// The current app theme
    var theme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - View Extensions

extension View {
    /// Injects the current theme into the environment
    func withTheme(_ theme: AppTheme) -> some View {
        self.environment(\.theme, theme)
    }

    /// Injects the theme manager's current theme
    func withThemeManager() -> some View {
        self.environment(\.theme, ThemeManager.shared.current)
    }
}
