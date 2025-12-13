//
//  GlassColors.swift
//  llmHub
//
//  Semantic glass tint colors for consistent visual language.
//

import SwiftUI

extension Color {
    // MARK: - Glass Tints (use with .glassEffect(.regular.tint()))

    /// Success state - tool completed, message sent
    static let glassSuccess = Color.green.opacity(0.25)

    /// Warning state - rate limit approaching, large context
    static let glassWarning = Color.orange.opacity(0.25)

    /// Error state - failed request, tool error
    static let glassError = Color.red.opacity(0.25)

    /// Accent/Active state - selected item, focused input
    static let glassAccent = Color.accentColor.opacity(0.25)

    /// AI/Assistant identity - messages from LLM
    static let glassAI = Color.purple.opacity(0.2)

    /// User identity - messages from user
    static let glassUser = Color.blue.opacity(0.15)

    /// Glass background - general background tint
    static let glassBackground = Color.black.opacity(0.1)

    /// Tool execution - active tool operations
    static let glassTool = Color.cyan.opacity(0.2)

    // MARK: - Legacy Neon Colors (for gradual migration)
    // Keep these temporarily, but prefer glass tints for new code

    static let neonElectricBlue = Color(red: 0.0, green: 0.7, blue: 1.0)
    static let neonFuchsia = Color(red: 1.0, green: 0.0, blue: 0.6)
    static let neonMidnight = Color(red: 0.05, green: 0.05, blue: 0.1)
    static let neonCharcoal = Color(red: 0.12, green: 0.12, blue: 0.15)
    static let neonGray = Color(red: 0.6, green: 0.6, blue: 0.65)
}
