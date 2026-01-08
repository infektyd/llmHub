//
//  UIAppearance.swift
//  llmHub
//
//  Shared UI appearance environment values derived from AppSettings.
//

import SwiftUI

// MARK: - Environment Keys

private struct UIScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

private struct UICompactModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// Global UI scale factor (wired to `AppSettings.fontSize`).
    var uiScale: CGFloat {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }

    /// Global compact mode toggle (wired to `AppSettings.compactMode`).
    var uiCompactMode: Bool {
        get { self[UICompactModeKey.self] }
        set { self[UICompactModeKey.self] = newValue }
    }
}

// MARK: - Helpers

extension View {
    /// Injects global appearance values into the environment.
    func applyUIAppearance(from settings: AppSettings) -> some View {
        environment(\.uiScale, settings.fontSize)
            .environment(\.uiCompactMode, settings.compactMode)
    }
}
