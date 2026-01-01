import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

struct AppColors {
    // MARK: - Dynamic System Adaptive Colors

    private static func adaptiveColor(dark: Color, light: Color) -> Color {
        #if canImport(UIKit)
        Color(
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
            }
        )
        #elseif canImport(AppKit)
        Color(
            NSColor(
                name: nil,
                dynamicProvider: { appearance in
                    let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
                    return bestMatch == .darkAqua ? NSColor(dark) : NSColor(light)
                }
            )
        )
        #else
        dark
        #endif
    }

    // MARK: - Dark Mode (CanvasDarkTheme values)
    struct Dark {
        static let backgroundPrimary = Color(red: 0.10, green: 0.10, blue: 0.10)
        static let backgroundSecondary = Color(red: 0.15, green: 0.15, blue: 0.15)
        static let surface = Color(red: 0.18, green: 0.18, blue: 0.18)
        static let textPrimary = Color.white.opacity(0.92)
        static let textSecondary = Color.white.opacity(0.72)
        static let textTertiary = Color.white.opacity(0.52)
        static let accent = Color(red: 0.78, green: 0.44, blue: 0.28)
        static let accentSecondary = Color(red: 0.22, green: 0.64, blue: 0.52)
        static let success = Color(red: 0.23, green: 0.78, blue: 0.33)
        static let warning = Color(red: 0.96, green: 0.77, blue: 0.32)
        static let error = Color(red: 0.93, green: 0.33, blue: 0.31)
    }

    // MARK: - Light Mode (CanvasLightTheme values)
    struct Light {
        static let backgroundPrimary = Color(red: 0.96, green: 0.96, blue: 0.97)
        static let backgroundSecondary = Color(red: 0.93, green: 0.93, blue: 0.95)
        static let surface = Color.white
        static let textPrimary = Color.black.opacity(0.90)
        static let textSecondary = Color.black.opacity(0.70)
        static let textTertiary = Color.black.opacity(0.50)
        static let accent = Color(red: 0.72, green: 0.36, blue: 0.22)
        static let accentSecondary = Color(red: 0.18, green: 0.56, blue: 0.46)
        static let success = Color(red: 0.18, green: 0.62, blue: 0.28)
        static let warning = Color(red: 0.78, green: 0.52, blue: 0.10)
        static let error = Color(red: 0.79, green: 0.18, blue: 0.16)
    }

    // MARK: - Adaptive Colors (no ColorScheme required)

    static let backgroundPrimary: Color = adaptiveColor(
        dark: Dark.backgroundPrimary,
        light: Light.backgroundPrimary
    )
    static let backgroundSecondary: Color = adaptiveColor(
        dark: Dark.backgroundSecondary,
        light: Light.backgroundSecondary
    )
    static let surface: Color = adaptiveColor(dark: Dark.surface, light: Light.surface)

    static let textPrimary: Color = adaptiveColor(dark: Dark.textPrimary, light: Light.textPrimary)
    static let textSecondary: Color = adaptiveColor(dark: Dark.textSecondary, light: Light.textSecondary)
    static let textTertiary: Color = adaptiveColor(dark: Dark.textTertiary, light: Light.textTertiary)

    static let accent: Color = adaptiveColor(dark: Dark.accent, light: Light.accent)
    static let accentSecondary: Color = adaptiveColor(dark: Dark.accentSecondary, light: Light.accentSecondary)
    static let success: Color = adaptiveColor(dark: Dark.success, light: Light.success)
    static let warning: Color = adaptiveColor(dark: Dark.warning, light: Light.warning)
    static let error: Color = adaptiveColor(dark: Dark.error, light: Light.error)

    // MARK: - Adaptive Colors (explicit ColorScheme)

    static func backgroundPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.backgroundPrimary : Light.backgroundPrimary
    }
    static func backgroundSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.backgroundSecondary : Light.backgroundSecondary
    }
    static func surface(for scheme: ColorScheme) -> Color { scheme == .dark ? Dark.surface : Light.surface }
    static func textPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.textPrimary : Light.textPrimary
    }
    static func textSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.textSecondary : Light.textSecondary
    }
    static func textTertiary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.textTertiary : Light.textTertiary
    }
    static func accent(for scheme: ColorScheme) -> Color { scheme == .dark ? Dark.accent : Light.accent }
    static func accentSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.accentSecondary : Light.accentSecondary
    }
    static func success(for scheme: ColorScheme) -> Color { scheme == .dark ? Dark.success : Light.success }
    static func warning(for scheme: ColorScheme) -> Color { scheme == .dark ? Dark.warning : Light.warning }
    static func error(for scheme: ColorScheme) -> Color { scheme == .dark ? Dark.error : Light.error }

    // MARK: - Static Properties (CanvasDark values)
    static let monoFont: Font = .system(.body, design: .monospaced)
    static let bodyFont: Font = .system(size: 15)
    static let responseFont: Font = .system(size: 15)
    static let headingFont: Font = .system(size: 14, weight: .semibold)
    static let cornerRadius: CGFloat = 14
    static let borderWidth: CGFloat = 1
}