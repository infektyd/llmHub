//
//  LiquidGlassLightTheme.swift
//  llmHub
//
//  Airy, neutral system-native Liquid Glass theme (Light Mode).
//

import SwiftUI

struct LiquidGlassLightTheme: AppTheme {
    let name = "Liquid Glass Light"

    // MARK: - Backgrounds

    // Neutral light gray/white mix for the base, allowing system wallpaper to bleed through slightly if transparent
    var backgroundPrimary: Color { Color(red: 0.96, green: 0.96, blue: 0.97).opacity(0.6) }
    var backgroundSecondary: Color { Color(red: 0.98, green: 0.98, blue: 0.99).opacity(0.5) }

    // Frosted look for surfaces
    var surface: Color { Color.white.opacity(0.65) }

    // MARK: - Text

    var textPrimary: Color { Color.black.opacity(0.85) }
    var textSecondary: Color { Color.black.opacity(0.60) }
    var textTertiary: Color { Color.black.opacity(0.40) }

    // MARK: - Accent

    var accent: Color { Color.accentColor }  // Keep system accent for now
    var accentSecondary: Color { Color.accentColor.opacity(0.75) }
    var success: Color { Color(red: 0.2, green: 0.7, blue: 0.3) }
    var warning: Color { Color(red: 1.0, green: 0.6, blue: 0.0) }
    var error: Color { Color(red: 0.9, green: 0.2, blue: 0.2) }

    // MARK: - Typography

    var bodyFont: Font { .system(size: 16) }
    var responseFont: Font { .system(size: 16) }
    var monoFont: Font { .system(size: 13, design: .monospaced) }
    var headingFont: Font { .system(size: 18, weight: .semibold) }

    // MARK: - Visual Effects

    var usesGlassEffect: Bool { true }

    // Softer shadow for light mode
    var shadowStyle: ShadowStyle {
        ShadowStyle(
            color: Color.black.opacity(0.08),
            radius: 12,
            x: 0,
            y: 4
        )
    }

    var cornerRadius: CGFloat { 16 }
    var borderWidth: CGFloat { 1 }

    // MARK: - Glass Effect Tunables

    var glassSmokiness: CGFloat { 0.05 }  // Almost clear, airy
    var glassTintColor: Color { Color.white.opacity(0.3) }
    var glassBlurRadius: CGFloat { 30 }
}
