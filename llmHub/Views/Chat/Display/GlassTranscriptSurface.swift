//
//  GlassTranscriptSurface.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/12/25.
//

import SwiftUI

/// A container view that wraps the chat transcript in a continuous Liquid Glass surface.
struct GlassTranscriptSurface<Content: View, Footer: View>: View {
    let content: Content
    let footer: Footer

    init(@ViewBuilder content: () -> Content) where Footer == EmptyView {
        self.content = content()
        self.footer = EmptyView()
    }

    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            footer
        }
        .background {
            // Native glass surface for the entire transcript
            Color.clear
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(
                        cornerRadius: LiquidGlassTokens.Radius.sheet, style: .continuous))
        }
        .clipShape(
            RoundedRectangle(cornerRadius: LiquidGlassTokens.Radius.sheet, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LiquidGlassTokens.Radius.sheet, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(LiquidGlassTokens.Stroke.highlightTop),
                            .white.opacity(LiquidGlassTokens.Stroke.highlightBottom),
                            .clear.opacity(LiquidGlassTokens.Stroke.border),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: LiquidGlassTokens.Stroke.hairline
                )
        )
        .shadow(
            color: LiquidGlassTokens.Shadow.sheet.color,
            radius: LiquidGlassTokens.Shadow.sheet.radius,
            x: LiquidGlassTokens.Shadow.sheet.x,
            y: LiquidGlassTokens.Shadow.sheet.y
        )
    }
}

// MARK: - Previews

#Preview("Transcript Surface") {
    GlassTranscriptSurface {
        ScrollView {
            VStack(alignment: .leading) {
                Text("Chat Content")
                    .padding()
            }
        }
    } footer: {
        Text("Composer")
            .padding()
    }
    .padding(24)
    .previewEnvironment()
}
