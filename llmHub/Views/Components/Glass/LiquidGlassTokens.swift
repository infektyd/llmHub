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
        CanvasDarkTheme()
    }

    enum Radius {
        static let sheet: CGFloat = 11
        static let control: CGFloat = 07
        static let toolCard: CGFloat = 07
    }

    enum Spacing {
        static let sheetInset: CGFloat = 16
        static let transcriptPadding: CGFloat = 0
        static let rowHorizontal: CGFloat = 18
        static let rowVertical: CGFloat = 8
        static let rowGutter: CGFloat = 12
        static let markerWidth: CGFloat = 3.5  // Updated to 3-4px as per prompt
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

    // MARK: - Fonts (NEON: SF Mono; LIQUID: SF Pro; User Bold)
    static func messageFont(role: MessageRole, theme: AppTheme) -> Font {
        let baseFont: Font =
            theme.name.contains("Neon")
            ? .system(size: 16, design: .monospaced) : theme.responseFont
        return role == .user ? baseFont.bold() : baseFont
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
        let neonCyan = Color(hex: "00BFFF")
        let baseTint = theme.name.contains("Neon") ? neonCyan : Color.teal.opacity(0.3)
        switch role {
        case .user: return theme.accent.opacity(0.65)
        case .assistant: return baseTint.opacity(0.45)
        case .system: return Color.indigo.opacity(0.4)
        case .tool: return Color.mint.opacity(0.5)
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

// MARK: - Adaptive Glass Modifier

extension View {
    /// Applies glass effect if theme supports it, otherwise uses solid background with border
    @ViewBuilder
    func adaptiveGlass(theme: AppTheme, cornerRadius: CGFloat? = nil) -> some View {
        let radius = cornerRadius ?? theme.cornerRadius
        if theme.usesGlassEffect {
            self.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            self
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(theme.textTertiary.opacity(0.15), lineWidth: theme.borderWidth)
                )
        }
    }
}

// MARK: - Previews

#Preview("Token Showcase") {
    VStack(alignment: .leading, spacing: 20) {
        Text("Liquid Glass Design Tokens")
            .font(.title2.bold())
            .padding(.bottom)

        VStack(alignment: .leading, spacing: 12) {
            Text("Radius Values")
                .font(.headline)
            HStack(spacing: 16) {
                RadiusChip(name: "Sheet", radius: LiquidGlassTokens.Radius.sheet)
                RadiusChip(name: "Control", radius: LiquidGlassTokens.Radius.control)
                RadiusChip(name: "Tool Card", radius: LiquidGlassTokens.Radius.toolCard)
            }
        }

        VStack(alignment: .leading, spacing: 12) {
            Text("Role Labels & Tints")
                .font(.headline)

            ForEach([MessageRole.user, .assistant, .system, .tool], id: \.self) { role in
                HStack {
                    Text(LiquidGlassTokens.roleLabel(role))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 100, alignment: .leading)

                    Circle()
                        .fill(LiquidGlassTokens.roleTint(role, theme: CanvasDarkTheme()))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                }
            }
        }
    }
    .padding()
    .frame(width: 400)
    .background(Color.gray.opacity(0.05))
}

private struct RadiusChip: View {
    let name: String
    let radius: CGFloat

    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 60, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(Color.accentColor, lineWidth: 1)
                )

            Text(name)
                .font(.caption)
            Text("\(Int(radius))pt")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
