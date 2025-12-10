//
//  LiquidGlassTokens.swift
//  llmHub
//
//  Design tokens for Liquid Glass system - colors, typography, spacing.
//  Scaffolded for future integration; see LiquidGlassMigration.md for activation steps.
//

import SwiftUI

// MARK: - Design Tokens

struct LiquidGlassTokens {
    // MARK: - Colors
    
    struct Colors {
        // Background colors
        static let background = Color(red: 0.05, green: 0.05, blue: 0.1)
        static let backgroundSecondary = Color(red: 0.08, green: 0.08, blue: 0.13)
        static let surface = Color(red: 0.1, green: 0.1, blue: 0.15)
        static let surfaceSecondary = Color(red: 0.12, green: 0.12, blue: 0.18)
        
        // Glass tints
        struct Glass {
            static let neutral = Color.white.opacity(0.1)
            static let accent = Color.accentColor.opacity(0.2)
            static let success = Color.green.opacity(0.2)
            static let warning = Color.orange.opacity(0.2)
            static let error = Color.red.opacity(0.2)
            static let info = Color.blue.opacity(0.2)
        }
        
        // Semantic colors
        static let textPrimary = Color.white
        static let textSecondary = Color(red: 0.7, green: 0.7, blue: 0.8)
        static let textTertiary = Color(red: 0.5, green: 0.5, blue: 0.6)
        static let border = Color.white.opacity(0.1)
        static let borderStrong = Color.white.opacity(0.2)
        
        // Accent colors
        static let accent = Color(red: 0.0, green: 0.7, blue: 1.0)
        static let accentDark = Color(red: 0.0, green: 0.5, blue: 0.8)
        static let accentLight = Color(red: 0.3, green: 0.85, blue: 1.0)
        
        // Status colors
        static let success = Color(red: 0.2, green: 0.85, blue: 0.4)
        static let warning = Color(red: 1.0, green: 0.7, blue: 0.0)
        static let error = Color(red: 1.0, green: 0.3, blue: 0.3)
        static let info = Color(red: 0.3, green: 0.7, blue: 1.0)
    }
    
    // MARK: - Typography
    
    struct Typography {
        // Font sizes
        static let displayLarge: CGFloat = 32
        static let displayMedium: CGFloat = 28
        static let headingLarge: CGFloat = 24
        static let headingMedium: CGFloat = 20
        static let headingSmall: CGFloat = 16
        static let bodyLarge: CGFloat = 16
        static let bodyMedium: CGFloat = 14
        static let bodySmall: CGFloat = 12
        static let labelLarge: CGFloat = 14
        static let labelMedium: CGFloat = 12
        static let labelSmall: CGFloat = 11
        
        // Font weights
        static let thin = Font.Weight.thin
        static let light = Font.Weight.light
        static let regular = Font.Weight.regular
        static let medium = Font.Weight.medium
        static let semibold = Font.Weight.semibold
        static let bold = Font.Weight.bold
        static let heavy = Font.Weight.heavy
        
        // Preset fonts
        static func display(_ size: CGFloat = displayLarge, weight: Font.Weight = .bold) -> Font {
            .system(size: size, weight: weight, design: .default)
        }
        
        static func heading(_ size: CGFloat = headingLarge, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .default)
        }
        
        static func body(_ size: CGFloat = bodyMedium, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .default)
        }
        
        static func label(_ size: CGFloat = labelMedium, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .default)
        }
        
        static func mono(_ size: CGFloat = bodyMedium) -> Font {
            .system(size: size, weight: .regular, design: .monospaced)
        }
    }
    
    // MARK: - Spacing
    
    struct Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }
    
    // MARK: - Corner Radius
    
    struct Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let full: CGFloat = .infinity
    }
    
    // MARK: - Borders
    
    struct Borders {
        static let thin: CGFloat = 0.5
        static let regular: CGFloat = 1.0
        static let medium: CGFloat = 1.5
        static let thick: CGFloat = 2.0
    }
    
    // MARK: - Shadows
    
    struct Shadows {
        static let none = Shadow(
            color: .clear,
            radius: 0,
            x: 0,
            y: 0
        )
        
        static let sm = Shadow(
            color: Color.black.opacity(0.08),
            radius: 4,
            x: 0,
            y: 2
        )
        
        static let md = Shadow(
            color: Color.black.opacity(0.12),
            radius: 8,
            x: 0,
            y: 4
        )
        
        static let lg = Shadow(
            color: Color.black.opacity(0.15),
            radius: 12,
            x: 0,
            y: 6
        )
        
        static let xl = Shadow(
            color: Color.black.opacity(0.2),
            radius: 20,
            x: 0,
            y: 10
        )
    }
    
    // MARK: - Animations
    
    struct Animation {
        static let fast = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let normal = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.5)
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.7)
    }
}

// MARK: - Shadow Value Type

struct Shadow: Equatable {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - Convenient Extensions

extension CGFloat {
    static let spacing = LiquidGlassTokens.Spacing.self
    static let radius = LiquidGlassTokens.Radius.self
}

extension Color {
    static let liquid = LiquidGlassTokens.Colors.self
}

// MARK: - Gradient Presets

struct LiquidGradients {
    /// Primary accent gradient - cyan to blue
    static let accentGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color(red: 0.0, green: 0.7, blue: 1.0),
            Color(red: 0.0, green: 0.5, blue: 0.8)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Background gradient - deep blue to purple
    static let backgroundGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color(red: 0.05, green: 0.05, blue: 0.1),
            Color(red: 0.1, green: 0.05, blue: 0.15)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Success gradient - green variations
    static let successGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color(red: 0.2, green: 0.85, blue: 0.4),
            Color(red: 0.1, green: 0.7, blue: 0.3)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Warning gradient - orange variations
    static let warningGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color(red: 1.0, green: 0.7, blue: 0.0),
            Color(red: 0.9, green: 0.5, blue: 0.0)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Error gradient - red variations
    static let errorGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color(red: 1.0, green: 0.3, blue: 0.3),
            Color(red: 0.8, green: 0.1, blue: 0.1)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Preview

#Preview("Design Tokens") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            // Colors
            VStack(alignment: .leading, spacing: 12) {
                Text("Colors")
                    .font(.system(size: 18, weight: .bold))
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(LiquidGlassTokens.Colors.accent)
                        .frame(width: 40, height: 40)
                    Text("Accent")
                    Spacer()
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(LiquidGlassTokens.Colors.success)
                        .frame(width: 40, height: 40)
                    Text("Success")
                    Spacer()
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Typography sizes
            VStack(alignment: .leading, spacing: 12) {
                Text("Typography")
                    .font(.system(size: 18, weight: .bold))
                
                Text("Display Large")
                    .font(LiquidGlassTokens.Typography.display())
                
                Text("Heading Medium")
                    .font(LiquidGlassTokens.Typography.heading(.headingMedium))
                
                Text("Body Medium")
                    .font(LiquidGlassTokens.Typography.body())
            }
            
            // Spacing
            VStack(alignment: .leading, spacing: 12) {
                Text("Spacing Scale")
                    .font(.system(size: 18, weight: .bold))
                
                ForEach([(name: "xs", value: LiquidGlassTokens.Spacing.xs),
                         (name: "md", value: LiquidGlassTokens.Spacing.md),
                         (name: "lg", value: LiquidGlassTokens.Spacing.lg)], id: \.name) { item in
                    HStack {
                        Text(item.name)
                            .frame(width: 40, alignment: .leading)
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: item.value, height: 20)
                        Text("\(Int(item.value))px")
                    }
                }
            }
        }
        .padding()
    }
    .background(LiquidGlassTokens.Colors.background)
    .foregroundStyle(LiquidGlassTokens.Colors.textPrimary)
}
