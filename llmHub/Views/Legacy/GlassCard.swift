//
//  GlassCard.swift
//  llmHub
//
//  Reusable glass card container for content panels.
//

import SwiftUI

struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let tint: Color?
    let isInteractive: Bool
    @ViewBuilder let content: Content

    init(
        cornerRadius: CGFloat = 16,
        tint: Color? = nil,
        isInteractive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.isInteractive = isInteractive
        self.content = content()
    }

    var body: some View {
        content
            .glassEffect(glassStyle, in: .rect(cornerRadius: cornerRadius))
    }

    private var glassStyle: GlassEffect {
        var style = GlassEffect.regular
        if let tint = tint {
            style = style.tint(tint)
        }
        if isInteractive {
            style = style.interactive()
        }
        return style
    }
}

// MARK: - Convenience Initializers

extension GlassCard where Content == EmptyView {
    /// Creates an empty glass card (use as background)
    init(cornerRadius: CGFloat = 16, tint: Color? = nil) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.isInteractive = false
        self.content = EmptyView()
    }
}

// MARK: - Preview

#Preview("Glass Cards") {
    VStack(spacing: 20) {
        GlassCard {
            Text("Default Glass Card")
                .padding()
        }

        GlassCard(tint: .glassAccent, isInteractive: true) {
            Text("Interactive Accent Card")
                .padding()
        }

        GlassCard(cornerRadius: 24, tint: .glassAI) {
            HStack {
                Image(systemName: "sparkles")
                Text("AI Response Card")
            }
            .padding()
        }
    }
    .padding()
    .background(Color.black)
}
