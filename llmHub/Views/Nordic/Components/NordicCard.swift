//
//  NordicCard.swift
//  llmHub
//
//  A clean surface card with subtle border. Debug-safe, no glass effects.
//

import SwiftUI

/// A minimalist card component with solid background and subtle border
struct NordicCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let content: Content
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12

    init(padding: CGFloat = 16, cornerRadius: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(NordicColors.surface(colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    /// Border color adapts to light/dark mode
    private var borderColor: Color {
        NordicColors.border(colorScheme)
    }
}

// MARK: - Previews

#Preview("Card with Text - Light") {
    NordicCard {
        VStack(alignment: .leading, spacing: 8) {
            Text("Card Title")
                .font(.headline)
            Text(
                "This is a sample card with some content inside. It has a clean surface and subtle border."
            )
            .font(.body)
            .foregroundColor(.secondary)
        }
    }
    .padding()
    .frame(width: 300)
    .preferredColorScheme(.light)
}

#Preview("Card with Text - Dark") {
    NordicCard {
        VStack(alignment: .leading, spacing: 8) {
            Text("Card Title")
                .font(.headline)
            Text(
                "This is a sample card with some content inside. It has a clean surface and subtle border."
            )
            .font(.body)
            .foregroundColor(.secondary)
        }
    }
    .padding()
    .frame(width: 300)
    .background(NordicColors.Dark.canvas)
    .preferredColorScheme(.dark)
}

#Preview("Multiple Cards") {
    VStack(spacing: 16) {
        NordicCard {
            Text("First Card")
                .font(.title3)
        }

        NordicCard(padding: 24) {
            VStack(spacing: 12) {
                Text("Second Card")
                    .font(.title3)
                Text("With more padding")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }

        NordicCard(cornerRadius: 20) {
            Text("Third Card with larger corner radius")
                .font(.body)
        }
    }
    .padding()
    .frame(width: 350)
}
