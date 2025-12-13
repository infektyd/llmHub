//
//  WarmPaperTheme.swift
//  llmHub
//
//  Claude-inspired warm, paper-like theme with a focus on readability.
//

import SwiftUI

/// A warm, paper-inspired theme reminiscent of Claude's aesthetic
struct WarmPaperTheme: AppTheme {
    let name = "Warm Paper"

    // MARK: - Backgrounds

    /// Warm cream background, like quality paper
    var backgroundPrimary: Color {
        Color(hex: "F4F3EE")
    }

    /// Slightly darker cream for panels
    var backgroundSecondary: Color {
        Color(hex: "EEEDEA")
    }

    /// Pure white for message surfaces
    var surface: Color {
        .white
    }

    // MARK: - Text Colors

    /// Soft charcoal for primary text
    var textPrimary: Color {
        Color(hex: "333333")
    }

    /// Medium gray for secondary text
    var textSecondary: Color {
        Color(hex: "666666")
    }

    /// Light gray for tertiary text
    var textTertiary: Color {
        Color(hex: "999999")
    }

    // MARK: - Accent Colors

    /// Terracotta accent inspired by Claude's palette
    var accent: Color {
        Color(hex: "D97757")
    }

    /// Deeper terracotta for hover states
    var accentSecondary: Color {
        Color(hex: "C4694B")
    }

    /// Warm green for success states
    var success: Color {
        Color(hex: "6B9E78")
    }

    /// Warm amber for warnings
    var warning: Color {
        Color(hex: "E8A857")
    }

    /// Warm red for errors
    var error: Color {
        Color(hex: "D86C5C")
    }

    // MARK: - Typography

    /// System font for UI elements
    var bodyFont: Font {
        .system(size: 16)
    }

    /// Serif font for AI responses (more readable, book-like)
    var responseFont: Font {
        .system(size: 17, design: .serif)
    }

    /// Monospace font for code
    var monoFont: Font {
        .system(size: 14, design: .monospaced)
    }

    /// Semibold system font for headings
    var headingFont: Font {
        .system(size: 18, weight: .semibold)
    }

    // MARK: - Visual Effects

    /// No glass effects in paper theme
    var usesGlassEffect: Bool {
        false
    }

    /// Subtle, soft shadows for depth
    var shadowStyle: ShadowStyle {
        ShadowStyle(
            color: Color.black.opacity(0.06),
            radius: 12,
            x: 0,
            y: 6
        )
    }

    /// Comfortable corner radius
    var cornerRadius: CGFloat {
        12
    }

    /// No border for paper theme
    var borderWidth: CGFloat {
        0
    }

    // MARK: - Glass Effect Tunables
    // These are not used by WarmPaperTheme but required by protocol

    var glassSmokiness: CGFloat {
        0.0
    }

    var glassTintColor: Color {
        .clear
    }

    var glassBlurRadius: CGFloat {
        0
    }
}
