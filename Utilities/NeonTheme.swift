//
//  NeonTheme.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftUI

// MARK: - Color Palette

extension Color {
    /// Electric Blue (#00BFFF) - Active states, tool execution, success
    static let neonElectricBlue = Color(red: 0, green: 0.75, blue: 1.0)

    /// Fuchsia (#FF0066) - Critical alerts, primary selection
    static let neonFuchsia = Color(red: 1.0, green: 0, blue: 0.4)

    /// Deep Charcoal - Primary background
    static let neonCharcoal = Color(red: 0.12, green: 0.12, blue: 0.15)

    /// Midnight - Secondary background
    static let neonMidnight = Color(red: 0.08, green: 0.08, blue: 0.10)

    /// Subtle Gray - Text and borders
    static let neonGray = Color(red: 0.6, green: 0.6, blue: 0.65)

    /// Initialize Color from Hex String
    init?(neonHex hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0

        guard Scanner(string: hex).scanHexInt64(&int) else {
            return nil
        }

        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 6:  // RGB
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  // ARGB
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
