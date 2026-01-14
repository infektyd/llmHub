//
//  MemoryIndicatorView.swift
//  llmHub
//
//  Created by Agent on 01/14/26.
//

import SwiftUI

/// Displays an indicator when memories are being used in the response.
struct MemoryIndicatorView: View {
    let count: Int
    let summary: String?
    @Binding var isVisible: Bool
    
    @State private var isAnimating = false
    @Environment(\.uiScale) private var uiScale
    
    var body: some View {
        if isVisible && count > 0 {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.system(size: 12 * uiScale, weight: .semibold))
                    .foregroundStyle(.purple)
                    .symbolEffect(.pulse, isActive: isAnimating)
                
                Text("\(count) \(count == 1 ? "memory" : "memories")")
                    .font(.system(size: 11 * uiScale, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.purple.opacity(0.1))
                    .overlay {
                        Capsule()
                            .stroke(.purple.opacity(0.3), lineWidth: 1)
                    }
            }
            .help(summary ?? "Memories used")
            .transition(.scale.combined(with: .opacity))
            .onAppear { isAnimating = true }
            .onDisappear { isAnimating = false }
        }
    }
}
