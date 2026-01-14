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
        /// Main background (deep charcoal, not pure black)
        static let backgroundPrimary = Color(red: 0.07, green: 0.07, blue: 0.08)

        /// Slight contrast layer (sidebar / secondary panels)
        static let backgroundSecondary = Color(red: 0.11, green: 0.11, blue: 0.13)

        /// Card / surface layer
        static let surface = Color(red: 0.14, green: 0.14, blue: 0.16)

        /// Text hierarchy (never pure white)
        static let textPrimary = Color.white.opacity(0.90)
        static let textSecondary = Color.white.opacity(0.70)
        static let textTertiary = Color.white.opacity(0.48)

        /// Warm accent (matches your Light accent family)
        static let accent = Color(red: 0.89, green: 0.56, blue: 0.42)

        /// Secondary accent (muted warm neutral)
        static let accentSecondary = Color(red: 0.62, green: 0.50, blue: 0.44)

        /// Success green
        static let success = Color(red: 0.34, green: 0.72, blue: 0.54)

        /// Shadow color used for elevated surfaces
        static let shadowSmoke = Color.black.opacity(0.32)

        /// Subtle user-message bubble background
        static let userBubble = Color.white.opacity(0.06)

        /// Neutral gray option for pickers
        static let smoke = Color(red: 0.55, green: 0.56, blue: 0.58)
    }
    
    enum Light {
        /// Main background (warm paper)
        static let backgroundPrimary = Color(red: 0.980, green: 0.976, blue: 0.961) // #FAF9F5-ish

        /// Slight contrast layer (subtle panel/background separation)
        static let backgroundSecondary = Color(red: 0.965, green: 0.960, blue: 0.945)

        /// Card / input field surface (nearly-white, still warm)
        static let surface = Color(red: 1.000, green: 0.998, blue: 0.992)

        /// Text uses softened black to match the calm look (avoid pure black)
        static let textPrimary = Color.black.opacity(0.78)
        static let textSecondary = Color.black.opacity(0.55)
        static let textTertiary = Color.black.opacity(0.38)

        /// Warm muted accent (star + send button vibe)
        static let accent = Color(red: 0.89, green: 0.56, blue: 0.42)

        /// Secondary accent (muted warm neutral accent for softer UI elements)
        static let accentSecondary = Color(red: 0.80, green: 0.62, blue: 0.52)

        /// Success green (soft, modern)
        static let success = Color(red: 0.32, green: 0.68, blue: 0.56)

        /// Shadow color used for elevated surfaces (very subtle in light mode)
        static let shadowSmoke = Color.black.opacity(0.08)

        /// Subtle user-message bubble background (barely-there ink)
        static let userBubble = Color.black.opacity(0.03)

        /// Neutral warm gray used as an option in UI pickers.
        static let smoke = Color(red: 0.68, green: 0.67, blue: 0.64)
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

    // MARK: - Explicit Theme Selection

    /// Returns a color for explicit light or dark mode (bypassing system theme).
    /// Use this when you need to show a specific theme for preview/export purposes.
    public static func color(for scheme: ColorScheme, dark: Color, light: Color) -> Color {
        scheme == .dark ? dark : light
    }

    /// Returns the appropriate palette based on color scheme selection.
    /// Used by the theme system to apply user's preferred color scheme.
    public static func palette(for scheme: ColorScheme?) -> Palette {
        switch scheme {
        case .none:
            return Palette(
                backgroundPrimary: backgroundPrimary,
                backgroundSecondary: backgroundSecondary,
                surface: surface,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                textTertiary: textTertiary,
                accent: accent,
                accentSecondary: accentSecondary,
                success: success,
                shadowSmoke: shadowSmoke,
                userBubble: userBubble,
                smoke: smoke
            )
        case .some(let resolvedScheme):
            switch resolvedScheme {
            case .dark:
                return Palette(
                    backgroundPrimary: Dark.backgroundPrimary,
                    backgroundSecondary: Dark.backgroundSecondary,
                    surface: Dark.surface,
                    textPrimary: Dark.textPrimary,
                    textSecondary: Dark.textSecondary,
                    textTertiary: Dark.textTertiary,
                    accent: Dark.accent,
                    accentSecondary: Dark.accentSecondary,
                    success: Dark.success,
                    shadowSmoke: Dark.shadowSmoke,
                    userBubble: Dark.userBubble,
                    smoke: Dark.smoke
                )
            case .light:
                return Palette(
                    backgroundPrimary: Light.backgroundPrimary,
                    backgroundSecondary: Light.backgroundSecondary,
                    surface: Light.surface,
                    textPrimary: Light.textPrimary,
                    textSecondary: Light.textSecondary,
                    textTertiary: Light.textTertiary,
                    accent: Light.accent,
                    accentSecondary: Light.accentSecondary,
                    success: Light.success,
                    shadowSmoke: Light.shadowSmoke,
                    userBubble: Light.userBubble,
                    smoke: Light.smoke
                )
            @unknown default:
                return Palette(
                    backgroundPrimary: backgroundPrimary,
                    backgroundSecondary: backgroundSecondary,
                    surface: surface,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    textTertiary: textTertiary,
                    accent: accent,
                    accentSecondary: accentSecondary,
                    success: success,
                    shadowSmoke: shadowSmoke,
                    userBubble: userBubble,
                    smoke: smoke
                )
            }
        }
    }

    /// Color palette struct for theme system
    public struct Palette {
        public let backgroundPrimary: Color
        public let backgroundSecondary: Color
        public let surface: Color
        public let textPrimary: Color
        public let textSecondary: Color
        public let textTertiary: Color
        public let accent: Color
        public let accentSecondary: Color
        public let success: Color
        public let shadowSmoke: Color
        public let userBubble: Color
        public let smoke: Color
    }

    static let backgroundPrimary: Color = adaptiveColor(
        dark: Dark.backgroundPrimary, light: Light.backgroundPrimary)
    static let backgroundSecondary: Color = adaptiveColor(
        dark: Dark.backgroundSecondary, light: Light.backgroundSecondary)

    static let surface: Color = adaptiveColor(dark: Dark.surface, light: Light.surface)

    static let textPrimary: Color = adaptiveColor(dark: Dark.textPrimary, light: Light.textPrimary)
    static let textSecondary: Color = adaptiveColor(
        dark: Dark.textSecondary, light: Light.textSecondary)
    static let textTertiary: Color = adaptiveColor(
        dark: Dark.textTertiary, light: Light.textTertiary)

    static let accent: Color = adaptiveColor(dark: Dark.accent, light: Light.accent)
    static let accentSecondary: Color = adaptiveColor(
        dark: Dark.accentSecondary, light: Light.accentSecondary)

    static let success: Color = adaptiveColor(dark: Dark.success, light: Light.success)

    /// Shadow color used for elevated surfaces.
    static let shadowSmoke: Color = adaptiveColor(dark: Dark.shadowSmoke, light: Light.shadowSmoke)

    /// Subtle user-message bubble background.
    static let userBubble: Color = adaptiveColor(dark: Dark.userBubble, light: Light.userBubble)

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
