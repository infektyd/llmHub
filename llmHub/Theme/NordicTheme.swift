//
//  NordicTheme.swift
//  llmHub
//
//  Scandinavian minimalist theme with warm earth tones.
//  Supports automatic light/dark mode switching via @Environment(\.colorScheme).
//  Uses ZERO beta APIs - fully compatible with View Hierarchy Debugger.
//

import SwiftUI

/// A Scandinavian-inspired minimalist theme with warm earth tones
struct NordicTheme: AppTheme {
    let name = "Nordic"

    // Note: AppTheme is a struct protocol, so we can't use @Environment directly.
    // Instead, components using this theme will check colorScheme at render time.
    // The colors below are optimized for dark mode by default.

    // MARK: - Backgrounds (warm stone grays)

    /// Deep warm charcoal - Stone-900
    var backgroundPrimary: Color {
        Color(hex: "1C1917")
    }

    /// Slightly lighter warm stone - Stone-800
    var backgroundSecondary: Color {
        Color(hex: "292524")
    }

    /// Card surface color - Stone-800
    var surface: Color {
        Color(hex: "292524")
    }

    // MARK: - Text (warm off-whites)

    /// Primary text - warm off-white - Stone-50
    var textPrimary: Color {
        Color(hex: "FAFAF9")
    }

    /// Secondary text - medium stone - Stone-400
    var textSecondary: Color {
        Color(hex: "A8A29E")
    }

    /// Tertiary text - muted stone - Stone-500
    var textTertiary: Color {
        Color(hex: "78716C")
    }

    // MARK: - Accents (earth tones)

    /// Primary accent - terracotta
    var accent: Color {
        Color(hex: "CD6F4E")
    }

    /// Secondary accent - sage green
    var accentSecondary: Color {
        Color(hex: "7BA382")
    }

    // MARK: - Semantic Colors

    /// Success state - sage green
    var success: Color {
        Color(hex: "7BA382")
    }

    /// Warning state - amber
    var warning: Color {
        Color(hex: "F59E0B")
    }

    /// Error state - warm red
    var error: Color {
        Color(hex: "DC2626")
    }

    // MARK: - Typography

    /// Body text font
    var bodyFont: Font {
        .system(size: 15)
    }

    /// AI response font
    var responseFont: Font {
        .system(size: 15)
    }

    /// Monospace font for code
    var monoFont: Font {
        .system(size: 14, design: .monospaced)
    }

    /// Heading font
    var headingFont: Font {
        .system(size: 18, weight: .semibold)
    }

    // MARK: - Visual Properties (NO GLASS)

    /// This theme does NOT use glass effects
    var usesGlassEffect: Bool {
        false
    }

    /// Comfortable corner radius for Scandinavian aesthetic
    var cornerRadius: CGFloat {
        12
    }

    /// Subtle border width
    var borderWidth: CGFloat {
        1
    }

    /// Soft shadow for depth
    var shadowStyle: ShadowStyle {
        ShadowStyle(
            color: Color.black.opacity(0.2),
            radius: 8,
            x: 0,
            y: 2
        )
    }

    // MARK: - Glass Properties (disabled, protocol required)

    var glassSmokiness: CGFloat {
        0
    }

    var glassTintColor: Color {
        .clear
    }

    var glassBlurRadius: CGFloat {
        0
    }
}
