//
//  ThinkingIndicatorView.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/11/25.
//

import SwiftUI

/// A "living" thinking indicator with rotating gear animation.
/// Design spec: "Living Thinking Indicator" from Liquid Glass UI improvements.
struct ThinkingIndicatorView: View {
    let isThinking: Bool

    @State private var rotationAngle: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            // AI Avatar with sparkles
            Circle()
                .frame(width: 32, height: 32)
                .glassEffect(GlassEffect.regular.tint(Color.blue.opacity(0.9)), in: .circle)
                .overlay(
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(.white)
                        .symbolEffect(
                            .pulse.byLayer,
                            options: .repeating,
                            isActive: isThinking
                        )
                )

            // Rotating gear symbol
            Image(systemName: "gearshape")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(rotationAngle))

            // Thinking text
            Text("Thinking...")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()
        }
        .onAppear {
            if isThinking {
                startRotationAnimation()
            }
        }
        .onChange(of: isThinking) { _, newValue in
            if newValue {
                startRotationAnimation()
            } else {
                // Stop rotation when not thinking
                withAnimation(.easeOut(duration: 0.3)) {
                    rotationAngle = 0
                }
            }
        }
    }

    private func startRotationAnimation() {
        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
            rotationAngle = 360.0
        }
    }
}

#Preview {
    ThinkingIndicatorView(isThinking: true)
        .padding()
        .previewEnvironment()
}
