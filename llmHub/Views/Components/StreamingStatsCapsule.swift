//
//  StreamingStatsCapsule.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/14/25.
//

import SwiftUI

/// A floating glass capsule showing live token stats during active streaming.
/// Displays: inputTokens → estimatedOutputTokens • $cost
struct StreamingStatsCapsule: View {
    let inputTokens: Int
    let estimatedOutputTokens: Int
    let estimatedCost: Decimal

    private var formattedCost: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter.string(from: estimatedCost as NSDecimalNumber) ?? "$0.00"
    }

    var body: some View {
        HStack(spacing: 8) {
            // Token flow indicator
            HStack(spacing: 4) {
                Text("Reported: \(inputTokens)")
                    .fontWeight(.medium)
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("Est: \(estimatedOutputTokens)")
                    .fontWeight(.medium)
                    .contentTransition(.numericText())
            }

            Text("•")
                .foregroundStyle(.tertiary)

            // Cost estimate
            Text("Est: \(formattedCost)")
                .fontWeight(.medium)
                .contentTransition(.numericText())
        }
        .font(.caption2)
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                )
                .glassEffect(
                    Glass.regular,
                    in: .capsule
                )
        }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            StreamingStatsCapsule(
                inputTokens: 1532,
                estimatedOutputTokens: 45,
                estimatedCost: 0.001
            )

            StreamingStatsCapsule(
                inputTokens: 1532,
                estimatedOutputTokens: 489,
                estimatedCost: 0.02
            )
        }
    }
}
