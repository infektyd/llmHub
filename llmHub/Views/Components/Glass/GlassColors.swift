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
    static let glassSuccess = Color.green.opacity(0.45)

    /// Warning state - rate limit approaching, large context
    static let glassWarning = Color.orange.opacity(0.40)

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
    static let glassTool = Color.cyan.opacity(0.45)

    // MARK: - Legacy Neon Colors (for gradual migration)
    // Keep these temporarily, but prefer glass tints for new code

    static let neonElectricBlue = Color(red: 0.0, green: 0.7, blue: 1.0)
    static let neonCyan = Color(red: 0.0, green: 0.9, blue: 0.9)
    static let neonFuchsia = Color(red: 1.0, green: 0.0, blue: 0.6)
    static let neonMidnight = Color(red: 0.05, green: 0.05, blue: 0.1)
    static let neonCharcoal = Color(red: 0.12, green: 0.12, blue: 0.15)
    static let neonGray = Color(red: 0.6, green: 0.6, blue: 0.65)
}

// MARK: - Previews

#Preview("Glass Tints") {
    VStack(alignment: .leading, spacing: 12) {
        Text("Glass Semantic Colors")
            .font(.headline)
            .padding(.bottom, 4)

        Group {
            ColorRow(name: "Success", color: .glassSuccess)
            ColorRow(name: "Warning", color: .glassWarning)
            ColorRow(name: "Error", color: .glassError)
            ColorRow(name: "Accent", color: .glassAccent)
            ColorRow(name: "AI / Assistant", color: .glassAI)
            ColorRow(name: "User", color: .glassUser)
            ColorRow(name: "Tool", color: .glassTool)
            ColorRow(name: "Background", color: .glassBackground)
        }
    }
    .padding()
    .frame(width: 300)
}

private struct ColorRow: View {
    let name: String
    let color: Color

    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )

            Text(name)
                .font(.system(size: 14))

            Spacer()
        }
    }
}
