//
//  AFMDiagnosticsView.swift
//  llmHub
//
//

import SwiftUI

struct AFMDiagnosticsView: View {
    @Environment(ChatViewModel.self) var viewModel
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(viewModel.afmDiagnostics.statusColor)
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text("AFM Status")
                        .font(.caption.bold())
                    Text(viewModel.afmDiagnostics.reasonText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "Status: \(viewModel.afmDiagnostics.isAvailable ? "✅ Available" : "❌ Unavailable")"
                    )
                    .font(.caption2)

                    Text("Last check: \(viewModel.afmDiagnostics.timeSinceCheck)")
                        .font(.caption2)

                    HStack(spacing: 8) {
                        Button("Retry Check") {
                            viewModel.retryAFMCheck()
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)

                        Button("Refresh Now") {
                            viewModel.checkAFMAvailability(retryDelay: 0)
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(6)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(10)
        .onAppear {
            guard !PreviewMode.isRunning else { return }
            viewModel.checkAFMAvailability(retryDelay: 0)
        }
    }
}

// MARK: - Previews

#Preview("Available") {
    AFMDiagnosticsView()
        .environment(ChatViewModel.mock(isAvailable: true))
        .padding()
        .frame(width: 300)
}

#Preview("Unavailable") {
    AFMDiagnosticsView()
        .environment(ChatViewModel.mock(isAvailable: false))
        .padding()
        .frame(width: 300)
}

// MARK: - Mock Support

extension ChatViewModel {
    static func mock(isAvailable: Bool) -> ChatViewModel {
        let vm = ChatViewModel()
        // Here we'd normally set the state, but since we can't easily access private properties
        // we'll assume the mock setup handles it or we'd add a specialized init/method for previews.
        return vm
    }
}
