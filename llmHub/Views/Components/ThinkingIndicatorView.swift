//
//  ThinkingIndicatorView.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/11/25.
//

import SwiftUI

/// A "living" thinking indicator with pulsing sparkles animation.
/// Design spec: "Living Thinking Indicator" from Liquid Glass UI improvements.
struct ThinkingIndicatorView: View {
    let isThinking: Bool

    @State private var opacity: Double = 0.6
    @State private var animationTrigger: Bool = false

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

            // Thinking text
            Text("Thinking...")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            Spacer()
        }
        .opacity(opacity)
        .onAppear {
            if isThinking {
                startOpacityAnimation()
            }
        }
        .onChange(of: isThinking) { _, newValue in
            if newValue {
                startOpacityAnimation()
            } else {
                // Reset opacity when not thinking
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0.6
                }
            }
        }
    }

    private func startOpacityAnimation() {
        // Reset to base state first
        opacity = 0.6
        // Delay slightly to ensure state change is registered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(
                .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true)
            ) {
                opacity = 1.0
            }
        }
    }
}

#Preview {
    ZStack {
        Color.clear.ignoresSafeArea()

        VStack(spacing: 20) {
            ThinkingIndicatorView(isThinking: true)
                .padding()
        }
    }
}
