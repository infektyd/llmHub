//
//  Theme.swift
//  llmHub
//
//  Theme protocol defining the visual appearance of the application.
//

import SwiftUI

/// Represents a complete visual theme for the application
protocol AppTheme {
    /// Display name of the theme
    var name: String { get }

    // MARK: - Backgrounds

    /// Primary background color (main window background)
    var backgroundPrimary: Color { get }

    /// Secondary background color (panels, sidebars)
    var backgroundSecondary: Color { get }

    /// Surface color (cards, message bubbles)
    var surface: Color { get }

    // MARK: - Text Colors

    /// Primary text color
    var textPrimary: Color { get }

    /// Secondary text color (labels, hints)
    var textSecondary: Color { get }

    /// Tertiary text color (disabled, placeholders)
    var textTertiary: Color { get }

    // MARK: - Accent Colors

    /// Primary accent color (buttons, links, selections)
    var accent: Color { get }

    /// Secondary accent color (hover states, highlights)
    var accentSecondary: Color { get }

    /// Success state color
    var success: Color { get }

    /// Warning state color
    var warning: Color { get }

    /// Error state color
    var error: Color { get }

    // MARK: - Typography

    /// Font for body text
    var bodyFont: Font { get }

    /// Font for AI response text
    var responseFont: Font { get }

    /// Font for code and monospace content
    var monoFont: Font { get }

    /// Font for headings
    var headingFont: Font { get }

    // MARK: - Visual Effects

    /// Whether this theme uses glass morphism effects
    var usesGlassEffect: Bool { get }

    /// Default shadow style for elevated elements
    var shadowStyle: ShadowStyle { get }

    /// Corner radius for cards and panels
    var cornerRadius: CGFloat { get }

    /// Border width for outlined elements
    var borderWidth: CGFloat { get }

    // MARK: - Glass Effect Tunables

    /// Controls glass opacity (0.0 = clear, 1.0 = opaque)
    var glassSmokiness: CGFloat { get }

    /// Tint overlay color for glass surfaces
    var glassTintColor: Color { get }

    /// Background blur amount for glass effect
    var glassBlurRadius: CGFloat { get }
}

/// Describes shadow appearance
struct ShadowStyle: Equatable {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    init(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }

    static let none = ShadowStyle(color: .clear, radius: 0, x: 0, y: 0)

    static let subtle = ShadowStyle(
        color: Color.black.opacity(0.06),
        radius: 12,
        x: 0,
        y: 6
    )

    static let elevated = ShadowStyle(
        color: Color.black.opacity(0.12),
        radius: 20,
        x: 0,
        y: 10
    )

    static let neonGlow = ShadowStyle(
        color: Color(red: 1.0, green: 0.0, blue: 0.6).opacity(0.3),
        radius: 20,
        x: 0,
        y: 10
    )
}
