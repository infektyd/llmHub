import SwiftUI

/// Central color tokens for the app.
///
/// This file intentionally keeps everything in one place so the UI can reference
/// semantic colors (text/surface/background/etc.) without scattering raw values.
///
/// Colors are defined for both light and dark appearances and exposed via
/// `static let` tokens.
enum AppColors {

    // MARK: - Light / Dark palettes

    enum Dark {
        static let backgroundPrimary = Color(red: 0.07, green: 0.07, blue: 0.08)
        static let backgroundSecondary = Color(red: 0.10, green: 0.10, blue: 0.12)

        static let surface = Color(red: 0.12, green: 0.12, blue: 0.14)

        static let textPrimary = Color.white.opacity(0.92)
        static let textSecondary = Color.white.opacity(0.72)
        static let textTertiary = Color.white.opacity(0.50)

        static let accent = Color(red: 0.78, green: 0.44, blue: 0.28)
        static let accentSecondary = Color(red: 0.22, green: 0.64, blue: 0.52)

        static let success = Color(red: 0.22, green: 0.74, blue: 0.46)

        /// Shadow color used for elevated surfaces.
        static let shadowSmoke = Color.black.opacity(0.28)

        /// A neutral, slightly warm gray used as an option in UI pickers.
        static let smoke = Color(red: 0.55, green: 0.56, blue: 0.58)
    }

    enum Light {
        static let backgroundPrimary = Color(red: 0.98, green: 0.98, blue: 0.99)
        static let backgroundSecondary = Color(red: 0.94, green: 0.95, blue: 0.96)

        static let surface = Color.white

        static let textPrimary = Color.black.opacity(0.88)
        static let textSecondary = Color.black.opacity(0.66)
        static let textTertiary = Color.black.opacity(0.45)

        static let accent = Color(red: 0.72, green: 0.36, blue: 0.22)
        static let accentSecondary = Color(red: 0.18, green: 0.56, blue: 0.46)

        static let success = Color(red: 0.18, green: 0.62, blue: 0.38)

        /// Shadow color used for elevated surfaces.
        static let shadowSmoke = Color.black.opacity(0.10)

        /// A neutral, slightly warm gray used as an option in UI pickers.
        static let smoke = Color(red: 0.62, green: 0.63, blue: 0.65)
    }

    // MARK: - Typography

    static let monoFont: Font = .system(.body, design: .monospaced)

    // MARK: - Adaptive tokens

    private static func adaptiveColor(dark: Color, light: Color) -> Color {
        #if canImport(UIKit)
        return Color(
            UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(dark)
                    : UIColor(light)
            }
        )
        #else
        // macOS
        return Color(
            NSColor(name: nil) { appearance in
                (appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
                    ? NSColor(dark)
                    : NSColor(light)
            }
        )
        #endif
    }

    static let backgroundPrimary: Color = adaptiveColor(dark: Dark.backgroundPrimary, light: Light.backgroundPrimary)
    static let backgroundSecondary: Color = adaptiveColor(dark: Dark.backgroundSecondary, light: Light.backgroundSecondary)

    static let surface: Color = adaptiveColor(dark: Dark.surface, light: Light.surface)

    static let textPrimary: Color = adaptiveColor(dark: Dark.textPrimary, light: Light.textPrimary)
    static let textSecondary: Color = adaptiveColor(dark: Dark.textSecondary, light: Light.textSecondary)
    static let textTertiary: Color = adaptiveColor(dark: Dark.textTertiary, light: Light.textTertiary)

    static let accent: Color = adaptiveColor(dark: Dark.accent, light: Light.accent)
    static let accentSecondary: Color = adaptiveColor(dark: Dark.accentSecondary, light: Light.accentSecondary)

    static let success: Color = adaptiveColor(dark: Dark.success, light: Light.success)

    /// Shadow color used for elevated surfaces.
    static let shadowSmoke: Color = adaptiveColor(dark: Dark.shadowSmoke, light: Light.shadowSmoke)

    /// A neutral gray option you can reference from UI pickers.
    static let smoke: Color = adaptiveColor(dark: Dark.smoke, light: Light.smoke)

    // MARK: - Central lists (for UI pickers)

    /// A small, centralized list of colors intended for UI selection.
    ///
    /// If you add a new option (like `smoke`), include it here so all pickers
    /// stay in sync.
    static let selectableAccents: [Color] = [
        accent,
        accentSecondary,
        smoke
    ]
}
