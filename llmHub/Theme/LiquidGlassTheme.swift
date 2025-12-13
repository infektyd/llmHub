//
//  LiquidGlassTheme.swift
//  llmHub
//
//  Neutral, system-native Liquid Glass theme for the unified interface.
//

import SwiftUI

struct LiquidGlassTheme: AppTheme {
    let name = "Liquid Glass"

    // MARK: - Backgrounds

    var backgroundPrimary: Color { Color.black.opacity(0.001) }
    var backgroundSecondary: Color { Color.black.opacity(0.001) }
    var surface: Color { Color.white.opacity(0.06) }

    // MARK: - Text

    var textPrimary: Color { .primary }
    var textSecondary: Color { .secondary }
    var textTertiary: Color { .secondary.opacity(0.75) }

    // MARK: - Accent

    var accent: Color { .accentColor }
    var accentSecondary: Color { .accentColor.opacity(0.75) }
    var success: Color { .green }
    var warning: Color { .orange }
    var error: Color { .red }

    // MARK: - Typography

    var bodyFont: Font { .system(size: 16) }
    var responseFont: Font { .system(size: 16) }
    var monoFont: Font { .system(size: 13, design: .monospaced) }
    var headingFont: Font { .system(size: 18, weight: .semibold) }

    // MARK: - Visual Effects

    var usesGlassEffect: Bool { true }
    var shadowStyle: ShadowStyle { .subtle }
    var cornerRadius: CGFloat { 14 }
    var borderWidth: CGFloat { 1 }

    // MARK: - Glass Effect Tunables

    var glassSmokiness: CGFloat { 0.12 }
    var glassTintColor: Color { .clear }
    var glassBlurRadius: CGFloat { 22 }
}

