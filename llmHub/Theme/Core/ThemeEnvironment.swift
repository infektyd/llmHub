//
//  ThemeEnvironment.swift
//  llmHub
//
//  Provides `EnvironmentValues.theme` so views can read the current `AppTheme`
//  using `@Environment(\\.theme)`.
//

import SwiftUI

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: any AppTheme = NeonGlassTheme()
}

extension EnvironmentValues {
    /// The active visual theme for the app.
    ///
    /// Rationale: Views use `@Environment(\\.theme)` for theme-driven styling. We keep a
    /// concrete default to ensure previews and tests build even if no explicit theme is injected.
    var theme: any AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

