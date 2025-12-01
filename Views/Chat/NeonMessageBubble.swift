//
//  NeonMessageBubble.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftUI

struct NeonMessageBubble: View {
    let message: ChatMessageEntity

    var isUser: Bool {
        message.role == MessageRole.user.rawValue
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !isUser {
                // AI Avatar
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.neonElectricBlue, .neonFuchsia],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    )
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                isUser
                                    ? Color.neonCharcoal.opacity(0.6)
                                    : Color.neonCharcoal.opacity(0.4)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        isUser
                                            ? Color.neonGray.opacity(0.2)
                                            : Color.neonElectricBlue.opacity(0.3),
                                        lineWidth: 1
                                    )
                            )
                    )
            }
            .frame(maxWidth: 600, alignment: isUser ? .trailing : .leading)

            if isUser {
                // User Avatar
                Circle()
                    .fill(Color.neonGray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.neonGray)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}
