//
//  NordicColors.swift
//  llmHub
//
//  Color palette for Nordic theme with light/dark mode support.
//  ZERO beta APIs - fully compatible with View Hierarchy Debugger.
//

import SwiftUI

/// Nordic color palette with automatic light/dark mode adaptation
struct NordicColors {

    // MARK: - Light Mode

    struct Light {
        static let canvas = Color(red: 0.961, green: 0.953, blue: 0.941)  // F5F3F0 - Warm light gray
        static let surface = Color.white  // Pure white for raised elements
        static let sidebar = Color.white  // Sidebar uses surface color (raised panel)
        static let border = Color(red: 0.906, green: 0.898, blue: 0.894)  // E7E5E4

        static let textPrimary = Color(red: 0.11, green: 0.098, blue: 0.09)  // 1C1917
        static let textSecondary = Color(red: 0.341, green: 0.325, blue: 0.306)  // 57534E
        static let textMuted = Color(red: 0.659, green: 0.635, blue: 0.62)  // A8A29E

        static let accentPrimary = Color(red: 0.706, green: 0.353, blue: 0.235)  // B45A3C - Terracotta
        static let accentSecondary = Color(red: 0.42, green: 0.561, blue: 0.443)  // 6B8F71 - Sage green
    }

    // MARK: - Dark Mode

    struct Dark {
        static let canvas = Color(red: 0.11, green: 0.098, blue: 0.09)  // 1C1917 - Warm charcoal
        static let surface = Color(red: 0.161, green: 0.145, blue: 0.141)  // 292524 - Slightly lighter for raised
        static let sidebar = Color(red: 0.161, green: 0.145, blue: 0.141)  // 292524 - Sidebar uses surface color
        static let border = Color(red: 0.267, green: 0.251, blue: 0.235)  // 44403C

        static let textPrimary = Color(red: 0.98, green: 0.98, blue: 0.976)  // FAFAF9
        static let textSecondary = Color(red: 0.659, green: 0.635, blue: 0.62)  // A8A29E
        static let textMuted = Color(red: 0.471, green: 0.443, blue: 0.424)  // 78716C

        static let accentPrimary = Color(red: 0.804, green: 0.435, blue: 0.306)  // CD6F4E - Lighter terracotta
        static let accentSecondary = Color(red: 0.482, green: 0.639, blue: 0.51)  // 7BA382 - Lighter sage
    }

    // MARK: - Adaptive Helpers

    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.canvas : Light.canvas
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.surface : Light.surface
    }

    static func sidebar(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.sidebar : Light.sidebar
    }

    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.border : Light.border
    }

    static func textPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.textPrimary : Light.textPrimary
    }

    static func textSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.textSecondary : Light.textSecondary
    }

    static func textMuted(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.textMuted : Light.textMuted
    }

    static func accentPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.accentPrimary : Light.accentPrimary
    }

    static func accentSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.accentSecondary : Light.accentSecondary
    }
}

// MARK: - Previews

#Preview("Light Mode Colors") {
    VStack(spacing: 20) {
        Text("Nordic Colors - Light Mode")
            .font(.title2.bold())

        VStack(spacing: 12) {
            ColorSwatch(name: "Canvas", color: NordicColors.Light.canvas)
            ColorSwatch(name: "Surface", color: NordicColors.Light.surface)
            ColorSwatch(name: "Sidebar", color: NordicColors.Light.sidebar)
            ColorSwatch(name: "Border", color: NordicColors.Light.border)
            ColorSwatch(name: "Text Primary", color: NordicColors.Light.textPrimary)
            ColorSwatch(name: "Text Secondary", color: NordicColors.Light.textSecondary)
            ColorSwatch(name: "Text Muted", color: NordicColors.Light.textMuted)
            ColorSwatch(
                name: "Accent Primary (Terracotta)", color: NordicColors.Light.accentPrimary)
            ColorSwatch(name: "Accent Secondary (Sage)", color: NordicColors.Light.accentSecondary)
        }
    }
    .padding()
    .previewEnvironment()
}

#Preview("Dark Mode Colors") {
    VStack(spacing: 20) {
        Text("Nordic Colors - Dark Mode")
            .font(.title2.bold())

        VStack(spacing: 12) {
            ColorSwatch(name: "Canvas", color: NordicColors.Dark.canvas)
            ColorSwatch(name: "Surface", color: NordicColors.Dark.surface)
            ColorSwatch(name: "Sidebar", color: NordicColors.Dark.sidebar)
            ColorSwatch(name: "Border", color: NordicColors.Dark.border)
            ColorSwatch(name: "Text Primary", color: NordicColors.Dark.textPrimary)
            ColorSwatch(name: "Text Secondary", color: NordicColors.Dark.textSecondary)
            ColorSwatch(name: "Text Muted", color: NordicColors.Dark.textMuted)
            ColorSwatch(name: "Accent Primary (Terracotta)", color: NordicColors.Dark.accentPrimary)
            ColorSwatch(name: "Accent Secondary (Sage)", color: NordicColors.Dark.accentSecondary)
        }
    }
    .padding()
    .previewEnvironment()
}

// Helper view for color swatches
private struct ColorSwatch: View {
    let name: String
    let color: Color

    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 60, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            Text(name)
                .font(.system(size: 14))

            Spacer()
        }
    }
}
