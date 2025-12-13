//
//  TokenUsageCapsule.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/11/25.
//

import SwiftUI

/// A floating glass capsule displaying token usage statistics.
/// Design spec: "Floating Glass Capsule" from Liquid Glass UI improvements.
struct TokenUsageCapsule: View {
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let totalCost: Decimal
    let contextLimit: Int

    @AppStorage("glassOpacity_statusBar") private var glassOpacity: Double = 0.85

    private var totalTokens: Int {
        inputTokens + outputTokens
    }

    private var percentUsed: Double {
        guard contextLimit > 0 else { return 0 }
        return min(Double(totalTokens) / Double(contextLimit) * 100, 100)
    }

    private var formattedCost: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter.string(from: totalCost as NSDecimalNumber) ?? "$0.00"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Input Tokens (Context)
            HStack(spacing: 4) {
                Text("❄️")
                    .font(.caption2)
                Text("\(inputTokens)")
                    .fontWeight(.medium)
            }

            Divider()
                .frame(height: 14)

            // Output Tokens (Generated)
            HStack(spacing: 4) {
                Text("⚡️")
                    .font(.caption2)
                Text("\(outputTokens)")
                    .fontWeight(.medium)
            }

            Divider()
                .frame(height: 14)

            // Cost
            HStack(spacing: 4) {
                Text("💲")
                    .font(.caption2)
                Text(formattedCost)
                    .fontWeight(.medium)
            }
        }
        .font(.caption2)
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                )
                .glassEffect(
                    GlassEffect.regular,
                    in: .capsule
                )
        }
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    private var percentColor: Color {
        switch percentUsed {
        case 0..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            TokenUsageCapsule(
                inputTokens: 1532,
                outputTokens: 489,
                cachedTokens: 0,
                totalCost: 0.02,
                contextLimit: 128000
            )

            TokenUsageCapsule(
                inputTokens: 85000,
                outputTokens: 12000,
                cachedTokens: 5000,
                totalCost: 1.45,
                contextLimit: 128000
            )
        }
    }
}
