//
//  NeonGlassTheme.swift
//  llmHub
//
//  The original futuristic glass morphism theme with neon accents.
//

import SwiftUI

/// A futuristic theme with glass morphism effects and neon accents
struct NeonGlassTheme: AppTheme {
    let name = "Neon Glass"

    // MARK: - Backgrounds

    /// Deep midnight background
    var backgroundPrimary: Color {
        Color(hex: "050505")  // neonMidnight
    }

    /// Charcoal for secondary surfaces
    var backgroundSecondary: Color {
        Color(hex: "1E1E26")  // neonCharcoal
    }

    /// Glass surface with material effects
    var surface: Color {
        Color.white.opacity(0.05)
    }

    // MARK: - Text Colors

    /// Pure white for primary text
    var textPrimary: Color {
        .white
    }

    /// Light gray for secondary text
    var textSecondary: Color {
        Color(hex: "999AA3")  // neonGray
    }

    /// Dimmed gray for tertiary text
    var textTertiary: Color {
        Color(hex: "666670")
    }

    // MARK: - Accent Colors

    /// Electric blue accent
    var accent: Color {
        Color(hex: "00BFFF")  // neonElectricBlue
    }

    /// Fuchsia secondary accent
    var accentSecondary: Color {
        Color(hex: "FF0099")  // neonFuchsia
    }

    /// Neon green for success
    var success: Color {
        Color(hex: "00FF88")
    }

    /// Neon amber for warnings
    var warning: Color {
        Color(hex: "FFB800")
    }

    /// Neon red for errors
    var error: Color {
        Color(hex: "FF3366")
    }

    // MARK: - Typography

    /// System font for body text
    var bodyFont: Font {
        .system(size: 16)
    }

    /// Same as body for responses in neon theme
    var responseFont: Font {
        .system(size: 16)
    }

    /// Monospace font for code
    var monoFont: Font {
        .system(size: 16, design: .monospaced)
    }

    /// Bold system font for headings
    var headingFont: Font {
        .system(size: 18, weight: .bold)
    }

    // MARK: - Visual Effects

    /// Glass morphism enabled
    var usesGlassEffect: Bool {
        true
    }

    /// Neon glow shadow
    var shadowStyle: ShadowStyle {
        ShadowStyle(
            color: Color(hex: "FF0099").opacity(0.3),  // neonFuchsia glow
            radius: 20,
            x: 0,
            y: 10
        )
    }

    /// Smooth corner radius for glass elements
    var cornerRadius: CGFloat {
        16
    }

    /// Subtle border for glass elements
    var borderWidth: CGFloat {
        1.5
    }

    // MARK: - Glass Effect Tunables

    /// Subtle transparency for glass surfaces
    var glassSmokiness: CGFloat {
        0.15
    }

    /// No tint by default, preserving existing appearance
    var glassTintColor: Color {
        .clear
    }

    /// Moderate blur for glass backgrounds
    var glassBlurRadius: CGFloat {
        20
    }
    // MARK: - Glass Semantic Tints

    /// Tint for user message bubbles
    var glassUser: Color {
        accent.opacity(0.3)
    }

    /// Tint for AI message bubbles
    var glassAI: Color {
        accent.opacity(0.3)
    }

    /// Tint for tools/inspector
    var glassTool: Color {
        Color(hex: "00B3FF").opacity(0.2)  // neonElectricBlue
    }

    /// Tint for generic areas (sidebar, background)
    var glassBackground: Color {
        Color.black.opacity(0.4)
    }
}
