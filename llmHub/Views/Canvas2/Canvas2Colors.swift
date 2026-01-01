//
//  Canvas2Colors.swift
//  llmHub
//
//  Design tokens for Canvas2 UI (Matte/Flat Theme)
//

import SwiftUI

struct Canvas2Colors {
    // Matte Backgrounds
    static let matteBackground = Color(red: 0.96, green: 0.95, blue: 0.93)  // Warm paper-like matte
    static let panelBackground = Color.white

    // Borders
    static let panelBorder = Color.black.opacity(0.06)
    static let inputBorder = Color.black.opacity(0.08)

    // Shadows
    static let panelShadow = Color.black.opacity(0.08)

    // Text
    static let textPrimary = Color.black.opacity(0.87)
    static let textSecondary = Color.black.opacity(0.6)
    static let textSubtle = Color.black.opacity(0.4)

    // Accent
    static let accent = Color(red: 0.82, green: 0.35, blue: 0.25)  // Terracotta/Claude-like accent
}
