//
//  NordicWelcomeView.swift
//  llmHub
//
//  Empty state view for Nordic theme.
//  ZERO beta APIs - fully compatible with View Hierarchy Debugger.
//

import SwiftUI

/// Welcome/empty state view for Nordic theme
struct NordicWelcomeView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Icon
            Image(systemName: "message")
                .font(.system(size: 56))
                .foregroundColor(NordicColors.textMuted(colorScheme))
                .padding(.bottom, 8)

            // Title
            Text("Start a conversation")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(NordicColors.textPrimary(colorScheme))

            // Subtitle
            Text("Select a chat or create a new one")
                .font(.system(size: 15))
                .foregroundColor(NordicColors.textSecondary(colorScheme))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // NO .background() - floats on canvas
    }
}

// MARK: - Previews

#Preview("Light Mode") {
    NordicWelcomeView()
        .preferredColorScheme(.light)
        .frame(width: 600, height: 400)
}

#Preview("Dark Mode") {
    NordicWelcomeView()
        .preferredColorScheme(.dark)
        .frame(width: 600, height: 400)
}
