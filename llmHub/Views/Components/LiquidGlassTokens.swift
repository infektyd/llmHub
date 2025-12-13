//
//  LiquidGlassTokens.swift
//  llmHub
//
//  Shared design tokens for the unified Liquid Glass interface.
//

import SwiftUI

enum LiquidGlassTokens {
    // MARK: - Dynamic Theme Access

    private static var theme: AppTheme {
        ThemeManager.shared.current
    }

    enum Radius {
        static let sheet: CGFloat = 22
        static let control: CGFloat = 14
        static let toolCard: CGFloat = 14
    }

    enum Spacing {
        static let sheetInset: CGFloat = 16
        static let transcriptPadding: CGFloat = 20
        static let rowHorizontal: CGFloat = 18
        static let rowVertical: CGFloat = 10
        static let rowGutter: CGFloat = 12
        static let markerWidth: CGFloat = 4  // Updated to 3-4px as per prompt
        static let composerPadding: CGFloat = 14
    }

    enum Stroke {
        static let hairline: CGFloat = 1

        static var highlightTop: Double {
            theme is LiquidGlassLightTheme ? 0.4 : 0.16
        }

        static var highlightBottom: Double {
            theme is LiquidGlassLightTheme ? 0.1 : 0.04
        }

        static var border: Double {
            theme is LiquidGlassLightTheme ? 0.08 : 0.12
        }

        static var toolCardBorder: Color {
            theme.textPrimary.opacity(theme is LiquidGlassLightTheme ? 0.08 : 0.12)
        }
    }

    enum Shadow {
        static var sheet: ShadowStyle {
            theme.shadowStyle
        }

        static var toolCard: ShadowStyle {
            if theme is LiquidGlassLightTheme {
                return ShadowStyle(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
            } else {
                return ShadowStyle(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 8)
            }
        }
    }

    // MARK: - Surfaces

    static var surfaceBackground: Material {
        if theme is LiquidGlassLightTheme {
            return .ultraThinMaterial
        } else {
            return .regularMaterial  // Or keep existing heavy glass logic
        }
    }

    static func roleTint(_ role: MessageRole, theme: AppTheme) -> Color {
        switch role {
        case .user:
            return theme.accent.opacity(0.85)
        case .assistant:
            return theme.textSecondary.opacity(0.75)
        case .system:
            return theme.textTertiary.opacity(0.7)
        case .tool:
            return theme.warning.opacity(0.85)
        }
    }

    static func roleLabel(_ role: MessageRole) -> String {
        switch role {
        case .user: return "You"
        case .assistant: return "Assistant"
        case .system: return "System"
        case .tool: return "Tool"
        }
    }
}
