//
//  LiquidFieldBackground.swift
//  llmHub
//
//  Soft neutral background that exists to prove translucency, not to draw attention.
//

import SwiftUI

struct LiquidFieldBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var opacity: Double = 1.0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [baseTop, baseBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(colorScheme == .dark ? 0.12 : 0.08),
                    .clear,
                ],
                center: .topTrailing,
                startRadius: 80,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    Color.clear.opacity(colorScheme == .dark ? 0.10 : 0.06),
                    .clear,
                ],
                center: .bottomLeading,
                startRadius: 120,
                endRadius: 680
            )
        }
        .opacity(opacity)
        .ignoresSafeArea()
    }

    private var baseTop: Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0.05, green: 0.06, blue: 0.08)
        default:
            return Color(red: 0.95, green: 0.95, blue: 0.96)
        }
    }

    private var baseBottom: Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0.08, green: 0.09, blue: 0.12)
        default:
            return Color(red: 0.90, green: 0.90, blue: 0.92)
        }
    }
}

#Preview {
    LiquidFieldBackground()
}

