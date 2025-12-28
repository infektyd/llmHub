//
//  ClaudeFlatTheme.swift
//  llmHub
//
//  Warm, flat dark theme inspired by Claude Desktop.
//

import SwiftUI

struct ClaudeFlatTheme: AppTheme {
    let name = "Claude Flat"

    // MARK: - Backgrounds (Warm dark grays, NOT pure black)
    var backgroundPrimary: Color { Color(hex: "1C1C1E") }
    var backgroundSecondary: Color { Color(hex: "2C2C2E") }
    var surface: Color { Color(hex: "3A3A3C") }

    // MARK: - Text (Off-white, not pure white)
    var textPrimary: Color { Color(hex: "F2F2F7") }
    var textSecondary: Color { Color(hex: "8E8E93") }
    var textTertiary: Color { Color(hex: "636366") }

    // MARK: - Accent (Claude's warm orange)
    var accent: Color { Color(hex: "E07A2D") }
    var accentSecondary: Color { Color(hex: "D97706") }

    // MARK: - Semantic
    var success: Color { Color(hex: "30D158") }
    var warning: Color { Color(hex: "FFD60A") }
    var error: Color { Color(hex: "FF453A") }

    // MARK: - Typography
    var bodyFont: Font { .system(size: 15) }
    var responseFont: Font { .system(size: 15) }
    var monoFont: Font { .system(size: 14, design: .monospaced) }
    var headingFont: Font { .system(size: 17, weight: .semibold) }

    // MARK: - Visual Effects (FLAT - no glass)
    var usesGlassEffect: Bool { false }
    var cornerRadius: CGFloat { 10 }
    var borderWidth: CGFloat { 0.5 }

    var shadowStyle: ShadowStyle {
        ShadowStyle(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 2)
    }

    // MARK: - Glass (disabled but protocol-required)
    var glassSmokiness: CGFloat { 0 }
    var glassTintColor: Color { .clear }
    var glassBlurRadius: CGFloat { 0 }
}
