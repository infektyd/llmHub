//
//  CanvasTheme.swift
//  llmHub
//
//  A neutral, screenshot-style theme (no neon/glass assumptions).
//

import SwiftUI

struct CanvasDarkTheme: AppTheme {
    let name: String = "Canvas Dark"

    var backgroundPrimary: Color { Color(red: 0.10, green: 0.10, blue: 0.10) }
    var backgroundSecondary: Color { Color(red: 0.15, green: 0.15, blue: 0.15) }
    var surface: Color { Color(red: 0.18, green: 0.18, blue: 0.18) }

    var textPrimary: Color { Color.white.opacity(0.92) }
    var textSecondary: Color { Color.white.opacity(0.72) }
    var textTertiary: Color { Color.white.opacity(0.52) }

    var accent: Color { Color(red: 0.78, green: 0.44, blue: 0.28) }
    var accentSecondary: Color { Color(red: 0.22, green: 0.64, blue: 0.52) }

    var success: Color { Color(red: 0.23, green: 0.78, blue: 0.33) }
    var warning: Color { Color(red: 0.96, green: 0.77, blue: 0.32) }
    var error: Color { Color(red: 0.93, green: 0.33, blue: 0.31) }

    var bodyFont: Font { .system(size: 15) }
    var responseFont: Font { .system(size: 15) }
    var monoFont: Font { .system(.body, design: .monospaced) }
    var headingFont: Font { .system(size: 14, weight: .semibold) }

    var usesGlassEffect: Bool { false }
    var shadowStyle: ShadowStyle { .elevated }
    var cornerRadius: CGFloat { 14 }
    var borderWidth: CGFloat { 1 }

    var glassSmokiness: CGFloat { 0 }
    var glassTintColor: Color { .clear }
    var glassBlurRadius: CGFloat { 0 }
}

struct CanvasLightTheme: AppTheme {
    let name: String = "Canvas Light"

    var backgroundPrimary: Color { Color(red: 0.96, green: 0.96, blue: 0.97) }
    var backgroundSecondary: Color { Color(red: 0.93, green: 0.93, blue: 0.95) }
    var surface: Color { .white }

    var textPrimary: Color { Color.black.opacity(0.90) }
    var textSecondary: Color { Color.black.opacity(0.70) }
    var textTertiary: Color { Color.black.opacity(0.50) }

    var accent: Color { Color(red: 0.72, green: 0.36, blue: 0.22) }
    var accentSecondary: Color { Color(red: 0.18, green: 0.56, blue: 0.46) }

    var success: Color { Color(red: 0.18, green: 0.62, blue: 0.28) }
    var warning: Color { Color(red: 0.78, green: 0.52, blue: 0.10) }
    var error: Color { Color(red: 0.79, green: 0.18, blue: 0.16) }

    var bodyFont: Font { .system(size: 15) }
    var responseFont: Font { .system(size: 15) }
    var monoFont: Font { .system(.body, design: .monospaced) }
    var headingFont: Font { .system(size: 14, weight: .semibold) }

    var usesGlassEffect: Bool { false }
    var shadowStyle: ShadowStyle { .subtle }
    var cornerRadius: CGFloat { 14 }
    var borderWidth: CGFloat { 1 }

    var glassSmokiness: CGFloat { 0 }
    var glassTintColor: Color { .clear }
    var glassBlurRadius: CGFloat { 0 }
}

