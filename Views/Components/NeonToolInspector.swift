//
//  NeonToolInspector.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftUI

struct NeonToolInspector: View {
    @Binding var isVisible: Bool
    @Binding var toolExecution: ToolExecution?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.neonElectricBlue)

                    Text("Tool Inspector")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        isVisible = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundColor(.neonGray)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.neonCharcoal.opacity(0.6))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.neonCharcoal.opacity(0.4))

            Divider()
                .background(Color.neonElectricBlue.opacity(0.3))

            // Content
            ScrollView {
                if let execution = toolExecution {
                    VStack(alignment: .leading, spacing: 16) {
                        // Tool Info
                        HStack(spacing: 12) {
                            Image(systemName: execution.icon)
                                .font(.system(size: 20))
                                .foregroundColor(.neonElectricBlue)
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(Color.neonCharcoal.opacity(0.6))
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(execution.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)

                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(execution.status.color)
                                        .frame(width: 6, height: 6)

                                    Text(statusText(execution.status))
                                        .font(.system(size: 11))
                                        .foregroundColor(.neonGray)
                                }
                            }

                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.neonCharcoal.opacity(0.4))
                        )

                        // Output
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Output")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.neonGray)

                            Text(execution.output)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.white)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.neonMidnight.opacity(0.8))
                                )
                        }
                    }
                    .padding(16)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.neonGray.opacity(0.3))

                        Text("No Active Tool")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.neonGray)

                        Text("Tool execution results will appear here")
                            .font(.system(size: 12))
                            .foregroundColor(.neonGray.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(.ultraThinMaterial)
                .overlay(Color.neonMidnight.opacity(0.5))
                .overlay(
                    // Electric Blue perimeter glow
                    Rectangle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .neonElectricBlue.opacity(0.6), .neonElectricBlue.opacity(0.2),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2
                        ),
                    alignment: .leading
                )
        )
    }

    private func statusText(_ status: ToolExecution.ExecutionStatus) -> String {
        switch status {
        case .pending: return "Pending"
        case .running: return "Running..."
        case .success: return "Completed"
        case .error: return "Error"
        }
    }
}
